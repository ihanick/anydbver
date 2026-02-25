ANYDBVER_BRIDGE = ENV["ANYDBVER_BRIDGE"] || ""
ANYDBVER_PUBNET = ENV["ANYDBVER_PUBNET"] || ""
$script = <<-'SCRIPT'
ANYDBVER_BRIDGE="$1"
apt-get update
snap refresh lxd --channel=latest/stable
apt-get install -y ansible git
apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
apt install -y docker-ce
gpasswd -a vagrant lxd
gpasswd -a vagrant docker
cd /home/vagrant/
git clone https://github.com/zelmario/anydbver.git
ln -s /home/vagrant/anydbver/anydbver /usr/local/bin/anydbver
cat >/home/vagrant/anydbver/.anydbver <<EOF
PROVIDER=docker
LXD_PROFILE=vagrant
K3S_FLANNEL_BACKEND=host-gw
EOF
if [ "x$ANYDBVER_BRIDGE" != "x" ] ; then
  cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8:
      dhcp4: no
      dhcp6: no
  bridges:
    br0:
      interfaces: [enp0s8]
      dhcp4: true
      mtu: 1500
      parameters:
        stp: true
        forward-delay: 4
EOF
  netplan generate
  netplan apply
fi

chown vagrant:vagrant -R /home/vagrant/anydbver
mkdir /home/vagrant/lxc
lxc storage create vagrant dir source=/home/vagrant/lxc
lxc profile create vagrant
lxc profile device add vagrant root disk type=disk pool=vagrant path=/

if [ "x$ANYDBVER_BRIDGE" != "x" ] ; then
  lxc profile device add vagrant eth0 nic name=eth0 nictype=bridged parent=br0 type=nic
else
  lxc network create lxdbr0
  lxc profile device add vagrant eth0 nic name=eth0 network=lxdbr0 type=nic
fi

echo 'export LXD_PROFILE=vagrant' >> /home/vagrant/.bashrc
echo 'export K3S_FLANNEL_BACKEND=host-gw' >> /home/vagrant/.bashrc
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

sudo -u vagrant bash -c 'export HOME=/home/vagrant;cd /home/vagrant/anydbver;./anydbver update; ansible-galaxy collection install theredgreek.sqlite ; cd /home/vagrant/anydbver/images-build ;  ./build.sh'

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
mv kubectl /usr/local/bin/
chmod +x /usr/local/bin/kubectl


SCRIPT

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  config.vm.synced_folder '.', '/vagrant', disabled: true

  if ANYDBVER_BRIDGE != "" || ANYDBVER_PUBNET != ""
    config.vm.network "public_network", use_dhcp_assigned_default_route: false
  end

  config.vm.provision "shell", inline: $script, args: ANYDBVER_BRIDGE

  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--uartmode1", "file", File::NULL]
    if ANYDBVER_BRIDGE != ""
      v.customize ["modifyvm", :id, "--nicpromisc2", "allow-all"]
    end
    v.memory = 8192
    v.cpus = 2
  end
end
