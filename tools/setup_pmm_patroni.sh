#!/bin/bash
# Setup PMM monitoring for Patroni-managed PostgreSQL
PASSWORD=$1
PMM_USER=${2:-pmm_user}
PMM_PASS=${3:-$PASSWORD}

NODE_IP=$(node_ip.sh)
export NODE_IP
export PATRONICTL_CONFIG_FILE=$(ls /etc/patroni/*.yml 2>/dev/null | head -1)

# Wait for Patroni to be ready and PostgreSQL to be running
# Replicas need to clone from primary first, which can take several minutes
echo "Waiting for Patroni to report this node as running..."
PG_READY=0
for i in {1..180}; do
    # Check Patroni API for this node's state
    STATE=$(curl -s http://localhost:8008/health 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('state',''))" 2>/dev/null)
    if [[ "$STATE" == "running" ]]; then
        # Verify PostgreSQL is actually accepting connections
        if sudo -u postgres psql -h localhost -c "SELECT 1" &>/dev/null; then
            echo "PostgreSQL is ready (state: $STATE)"
            PG_READY=1
            break
        fi
    fi
    echo "Waiting... (attempt $i, state: $STATE)"
    sleep 2
done

if [[ "$PG_READY" != "1" ]]; then
    echo "ERROR: PostgreSQL did not become ready within timeout"
    exit 1
fi

# Get cluster info from Patroni
CLUSTER_INFO=$(patronictl list -f json 2>/dev/null | python3 -c "
import sys, json, os
data = json.load(sys.stdin)
my_ip = os.environ.get('NODE_IP', '')
cluster_name = ''
my_role = 'replica'
for m in data:
    cluster_name = m.get('Cluster', '')
    if m.get('Host') == my_ip:
        my_role = m.get('Role', 'replica').lower().replace(' ', '_')
        if my_role in ('leader', 'standby_leader'):
            print(f'leader:{cluster_name}:{my_role}')
        else:
            print(f'replica:{cluster_name}:{my_role}')
        sys.exit(0)
print(f'replica:{cluster_name}:replica')
" 2>/dev/null || echo "replica:unknown:replica")

IS_LEADER=$(echo $CLUSTER_INFO | cut -d: -f1)
CLUSTER_NAME=$(echo $CLUSTER_INFO | cut -d: -f2)
PATRONI_ROLE=$(echo $CLUSTER_INFO | cut -d: -f3)
echo "Cluster: $CLUSTER_NAME, Role: $PATRONI_ROLE"

if [[ "$IS_LEADER" == "leader" ]]; then
    echo "This is the leader, creating PMM user..."
    sudo -u postgres psql -h localhost -c "CREATE USER $PMM_USER WITH ENCRYPTED PASSWORD '$PMM_PASS'" 2>/dev/null || true
    sudo -u postgres psql -h localhost -c "GRANT pg_monitor TO $PMM_USER" 2>/dev/null || true
    sudo -u postgres psql -h localhost -c "CREATE DATABASE $PMM_USER" 2>/dev/null || true
    sudo -u postgres psql -h localhost -d postgres -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements" 2>/dev/null || true
else
    echo "This is a replica, waiting for PMM user to be replicated..."
    for i in {1..60}; do
        if sudo -u postgres psql -h localhost -tAc "SELECT 1 FROM pg_roles WHERE rolname='$PMM_USER'" 2>/dev/null | grep -q 1; then
            echo "PMM user found"
            break
        fi
        sleep 2
    done
fi

# Add PostgreSQL to PMM with cluster name and labels
echo "Adding PostgreSQL to PMM..."
pmm-admin add postgresql --username=$PMM_USER --password="$PMM_PASS" \
    --cluster="$CLUSTER_NAME" \
    --custom-labels="role=$PATRONI_ROLE" \
    postgres-$(hostname) ${NODE_IP}:5432

touch /root/pmm-patroni.applied
