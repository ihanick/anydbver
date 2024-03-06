#!/bin/bash -e
MINIO_USER=UIdgE4sXPBTcBB4eEawU
MINIO_PASS=7UdlDzBF769dbIOMVILV
export MC_HOSTS_bkp=https://$MINIO_USER:$MINIO_PASS@172.17.0.1:9000
MC="tools/mc"
if ! [[ -f "$MC" ]] ; then
  curl https://dl.min.io/client/mc/release/linux-amd64/mc -o "$MC"
  chmod +x tools/mc
fi
mkdir -p data/minio
cat > data/minio-bkp-config.env <<EOF
MINIO_ROOT_USER=$MINIO_USER
MINIO_ROOT_PASSWORD=$MINIO_PASS
MINIO_VOLUMES="/mnt/data"
EOF
docker run -dt --restart unless-stopped -p 9000:9000 -p 9090:9090 \
  -v $PWD/data/minio-bkp-config.env:/etc/config.env \
  -e "MINIO_CONFIG_ENV_FILE=/etc/config.env" \
  -v $PWD/data/minio:/mnt/data \
  --name "minio_local" minio/minio server --console-address ":9090" --certs-dir /mnt/data/certs

until $MC alias set bkp https://172.17.0.1:9000 $MINIO_USER $MINIO_PASS ; do
  sleep 1
done

$MC mb bkp/sampledb

if ! [[ -d data/sampledb/world ]] ; then
  mkdir -p data/sampledb/world
  curl -sL https://downloads.mysql.com/docs/world-db.tar.gz |tar -C data/sampledb/world/ --strip-components 1 -xz
fi

$MC cp data/sampledb/world/world.sql bkp/sampledb/world.sql && true
if ! [[ -d data/sampledb/pagila ]] ; then
  mkdir -p data/sampledb/pagila
  curl -sL https://github.com/devrimgunduz/pagila/raw/master/pagila-schema.sql \
    https://github.com/devrimgunduz/pagila/raw/master/pagila-data.sql > data/sampledb/pagila/pagila.sql
fi

$MC cp data/sampledb/pagila/pagila.sql bkp/sampledb/pagila.sql && true

