# PXC=5.6.45-28.36.1 PXC56GALERA=3-3.36-1 PXB=2.3.9-1 vagrant up --provider=lxc
PS = ENV["PS"] || "" # "5.6.47-rel87.0.1" "5.7.29-32.1" "8.0.18-9.1"
PXC = ENV["PXC"] || "" # "5.6.45-28.36.1" "5.7.22-29.26.1" "8.0.18-9.3"
PXC_GALERA = ENV["PXC_GALERA"] || "" # "3-3.36-1"
PXB = ENV["PXB"] || "" # "2.3.9-1"
PSMDB = ENV["PSMDB"] || "" # "3.6.16-3.6"
PBM = ENV["PBM"] || "" # "1.1.1-1"
PMM_SERVER = ENV["PMM_SERVER"] || "" # "2.5.0"
PMM_CLIENT = ENV["PMM_CLIENT"] || "" # "2.5.0-6"
PPGSQL = ENV["PPGSQL"] || "" # "11.7-2"
PT = ENV["PT"] || "" # "3.2.0-1"
DB_USER = ENV["DB_USER"] || ""
DB_PASS = ENV["DB_PASS"] || ""
PKO4PXC = ENV["PKO4PXC"] || ""
PKO4PSMDB = ENV["PKO4PSMDB"] || ""
START = ENV["START"] || "" # START=1 to start systemd service automatically
DB_OPTS = ENV["DB_OPTS"] || "" # DB_OPTS=mysql/mysql-async-repl-gtid.cnf
LXD_PROFILE = ENV["LXD_PROFILE"] || "default"
OS = ENV["OS"] || "centos/7"
K3S = ENV["K3S"] || ""
K8S_PMM = ENV["K8S_PMM"] || ""
MASTER = ENV["MASTER"] || ""
REPLICATION_TYPE = ENV["REPLICATION_TYPE"] || ""
REPLICA_SET = ENV["REPLICA_SET"] || ""
PROXYSQL = ENV["PROXYSQL"] || ""
PERCONA_PROXYSQL = ENV["PERCONA_PROXYSQL"] || ""
MARIADB = ENV["MARIADB"] || ""
ORCHESTRATOR = ENV["ORCHESTRATOR"] || ""
DEBUG_PACKAGES = ENV["DEBUG_PACKAGES"] || ""

# get token from master k3s node: cat /var/lib/rancher/k3s/server/node-token
# if node re-added, kubectl delete node node1, and remove old entry from /var/lib/rancher/k3s/server/cred/node-passwd before run
K3S_TOKEN = ENV["K3S_TOKEN"] || ""
K3S_URL = ENV["K3S_URL"] || ""

if OS == "centos/7"
  LXC_BOX = "visibilityspots/centos-7.x-minimal"
elsif OS == "centos/8"
  LXC_BOX = "visibilityspots/centos-8.x-minimal"
elsif OS == "ubuntu/bionic64"
  LXC_BOX = "emptybox/ubuntu-bionic-amd64-lxc"
elsif OS == "ubuntu/focal64"
  LXC_BOX = "ubuntu/focal64"
end

Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.box = OS
  config.vm.provider "lxc" do |lxc, override|
    override.vm.box = LXC_BOX
    # https://app.vagrantup.com/visibilityspots/boxes/centos-7.x-minimal
    # override.vm.box_version = "7.7.0"
    #lxc.backingstore = 'dir'
    #lxc.backingstore_option '--dir','/bigdisk/lxc'
  end

  config.vm.provider "virtualbox" do |v|
    v.memory = 1024
    v.cpus = 2
  end
  config.vm.provider "lxd" do |lxd, override|
    lxd.nesting = true
    lxd.privileged = true
    lxd.profiles = [ LXD_PROFILE ]
    override.vm.box = LXC_BOX
  end

  config.vm.provision "shell" do |s|
    s.inline = "(grep -q vagrant /etc/passwd || useradd -m vagrant );mkdir -p /vagrant ; chown vagrant:adm /vagrant; chmod g+w -R /vagrant"
    s.privileged = true
  end
  config.vm.provision "file", source: "playbook.yml", destination: "/vagrant/playbook.yml"
  config.vm.provision "file", source: "configs", destination: "/vagrant/configs"
  config.vm.provision "file", source: "tools", destination: "/vagrant/tools"
  config.vm.provision "file", source: "common", destination: "/vagrant/common"
  config.vm.provision "file", source: "secret", destination: "/vagrant/secret"
  config.vm.provision "ansible_local" do |ansible|
    ansible.compatibility_mode = "2.0"
    ansible.playbook = "playbook.yml"
    ansible.verbose = false
    ansible.extra_vars = {
      extra_percona_server_version: PS,
      extra_percona_xtrabackup_version: PXB,
      extra_percona_xtradb_cluster_version: PXC,
      extra_percona_xtradb_cluster_galera: PXC_GALERA,
      extra_psmdb_version: PSMDB,
      extra_pbm_version: PBM,
      extra_pmm_server_version: PMM_SERVER,
      extra_pmm_client_version: PMM_CLIENT,
      extra_percona_postgresql_version: PPGSQL,
      extra_percona_toolkit_version: PT,
      extra_db_user: DB_USER,
      extra_db_password: DB_PASS,
      extra_percona_k8s_op_pxc_version: PKO4PXC,
      extra_percona_k8s_op_psmdb_version: PKO4PSMDB,
      extra_start_db: START,
      extra_db_opts_file: DB_OPTS,
      extra_k3s_token: K3S_TOKEN,
      extra_k3s_url: K3S_URL,
      extra_k3s_version: K3S,
      extra_k8s_pmm: K8S_PMM,
      extra_master_ip: MASTER,
      extra_replication_type: REPLICATION_TYPE,
      extra_mongo_replicaset: REPLICA_SET,
      extra_proxysql_version: PROXYSQL,
      extra_percona_proxysql_version: PERCONA_PROXYSQL,
      extra_mariadb_version: MARIADB,
      extra_orchestrator_version: ORCHESTRATOR,
      extra_debug_packages: DEBUG_PACKAGES,
    }
  end  

  config.vm.define "default", primary: true do |default|
    default.vm.hostname = "default"

    default.vm.provider "virtualbox" do |virtualbox, override|
      override.vm.network "private_network", ip: "192.168.38.4", virtualbox__intnet: true
    end
  end
  config.vm.define "node1", autostart: false do |node1|
    node1.vm.hostname = "node1"

    node1.vm.provider "virtualbox" do |virtualbox, override|
      override.vm.network "private_network", ip: "192.168.38.5", virtualbox__intnet: true
    end
  end
  config.vm.define "node2", autostart: false do |node2|
    node2.vm.hostname = "node2"

    node2.vm.provider "virtualbox" do |virtualbox, override|
      override.vm.network "private_network", ip: "192.168.38.6", virtualbox__intnet: true
    end
  end
  config.vm.define "node3", autostart: false do |node3|
    node3.vm.hostname = "node3"

    node3.vm.provider "virtualbox" do |virtualbox, override|
      override.vm.network "private_network", ip: "192.168.38.7", virtualbox__intnet: true
    end
  end
  config.vm.define "node4", autostart: false do |node4|
    node4.vm.hostname = "node4"

    node4.vm.provider "virtualbox" do |virtualbox, override|
      override.vm.network "private_network", ip: "192.168.38.8", virtualbox__intnet: true
    end
  end
  config.vm.define "node5", autostart: false do |node5|
    node5.vm.hostname = "node5"

    node5.vm.provider "virtualbox" do |virtualbox, override|
      override.vm.network "private_network", ip: "192.168.38.9", virtualbox__intnet: true
    end
  end 

end
