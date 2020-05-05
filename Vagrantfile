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

Vagrant.configure("2") do |config|
  config.vm.box = "centos/7"
  config.vm.provider "lxc" do |v, override|
    override.vm.box = "visibilityspots/centos-7.x-minimal"
    # https://app.vagrantup.com/visibilityspots/boxes/centos-7.x-minimal
    # override.vm.box_version = "7.7.0"
  end
  config.vm.provider "virtualbox" do |v|
    v.memory = 1024
    v.cpus = 2
  end

  config.vm.provision "ansible_local" do |ansible|
    ansible.compatibility_mode = "2.0"
    ansible.playbook = "playbook.yml"
    ansible.extra_vars = {
      percona_server_version: PS,
      percona_xtrabackup_version: PXB,
      percona_xtradb_cluster_version: PXC,
      percona_xtradb_cluster_galera: PXC_GALERA,
      psmdb_version: PSMDB,
      pbm_version: PBM,
      pmm_server_version: PMM_SERVER,
      pmm_client_version: PMM_CLIENT,
      percona_postgresql_version: PPGSQL,
      percona_toolkit_version: PT,
    }
  end  

  config.vm.define "default", primary: true do |default|
    default.vm.hostname = "default"
  end
  config.vm.define "node1", autostart: false do |node1|
    node1.vm.hostname = "node1"
  end
  config.vm.define "node2", autostart: false do |node2|
    node2.vm.hostname = "node2"
  end
  config.vm.define "node3", autostart: false do |node3|
    node3.vm.hostname = "node3"
  end
  config.vm.define "node4", autostart: false do |node4|
    node4.vm.hostname = "node4"
  end
  config.vm.define "node5", autostart: false do |node5|
    node5.vm.hostname = "node5"
  end 
end
