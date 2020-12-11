$script = <<-'SCRIPT'
apt-get update
apt-get install -y ansible git
gpasswd -a vagrant lxd
cd /home/vagrant/
git clone https://github.com/ihanick/anydbver.git
cat >/home/vagrant/anydbver/.anydbver <<EOF
PROVIDER=lxd
LXD_PROFILE=vagrant
K3S_FLANNEL_BACKEND=host-gw
EOF
chown vagrant:vagrant -R /home/vagrant/anydbver
mkdir /home/vagrant/lxc
lxc storage create vagrant dir source=/home/vagrant/lxc
lxc profile create vagrant
lxc profile device add vagrant root disk type=disk pool=vagrant path=/
lxc network create lxdbr0
lxc profile device add vagrant eth0 nic name=eth0 network=lxdbr0 type=nic
echo 'export LXD_PROFILE=vagrant' >> /home/vagrant/.bashrc
echo 'export K3S_FLANNEL_BACKEND=host-gw' >> /home/vagrant/.bashrc
sudo -u vagrant bash -c 'export HOME=/home/vagrant;cd /home/vagrant/anydbver;./anydbver update'
cat > /etc/sysctl.d/50-k3s.conf <<EOF
vm.overcommit_memory = 1
vm.overcommit_ratio = 10000
kernel.panic = 10
kernel.panic_on_oops = 1
EOF
sysctl -p /etc/sysctl.d/50-k3s.conf

cat > /etc/modules-load.d/k3s.conf <<EOF
br_netfilter
overlay
EOF
modprobe br_netfilter
modprobe overlay

SCRIPT

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  config.vm.synced_folder '.', '/vagrant', disabled: true

  config.vm.provision "shell", inline: $script

  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--uartmode1", "file", File::NULL]
    v.memory = 4096
    v.cpus = 2
  end
end
