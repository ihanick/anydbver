#!/bin/bash
test -f ../secret/id_rsa || ssh-keygen -t rsa -f ../secret/id_rsa -P '' && chmod 0600 ../secret/id_rsa


# centos7
lxc launch --profile $USER images:centos/7/amd64 $USER-default
until lxc exec $USER-default true ; do sleep 1 ; done
lxc file push ../secret/id_rsa.pub $USER-default/root/authorized_keys
lxc file push ../tools/node_ip.sh $USER-default/usr/bin/node_ip.sh
lxc file push ../tools/fix_el8_ip.sh $USER-default/usr/bin/fix_el8_ip.sh

lxc exec $USER-default -- bash -c 'export LANG=C;mkdir /root/.ssh;mv /root/authorized_keys /root/.ssh;bash /usr/bin/fix_el8_ip.sh;test -f /usr/bin/rsync || (until ping  -c 1 1.1.1.1 &>/dev/null ; do sleep 1; done; for pkg in sudo openssh-server iproute rsync dnsmasq ; do yum install -q -y $pkg ; done); chmod -R og-rwx /root/.ssh;sed -i -e '\''s/#UseDNS yes/UseDNS no/'\'' -e '\''s/#PermitRootLogin.*$/PermitRootLogin prohibit-password/'\'' /etc/ssh/sshd_config;sed '\''s@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g'\'' -i /etc/pam.d/sshd; chmod 0600 /root/.ssh/authorized_keys; chmod 0700 /root/.ssh; chown root:root -R /root/.ssh; yum install -q -y https://repo.percona.com/yum/release/7/RPMS/x86_64/libeatmydata-0.1-00.21.el7.centos.x86_64.rpm ; yum -y install openssh-server rsync python3 iproute procps-ng openssh-clients; yum clean all; systemctl enable sshd'
lxc stop $USER-default
lxc publish $USER-default --alias centos/7-sshd-systemd-$USER
lxc delete $USER-default

# Rocky8
lxc launch --profile $USER images:rockylinux/8/amd64 $USER-default
until lxc exec $USER-default true ; do sleep 1 ; done
lxc file push ../secret/id_rsa.pub $USER-default/root/authorized_keys
lxc file push ../tools/node_ip.sh $USER-default/usr/bin/node_ip.sh
lxc file push ../tools/fix_el8_ip.sh $USER-default/usr/bin/fix_el8_ip.sh

lxc exec $USER-default -- bash -c 'export LANG=C;mkdir /root/.ssh;mv /root/authorized_keys /root/.ssh;bash /usr/bin/fix_el8_ip.sh;test -f /usr/bin/rsync || (until ping  -c 1 1.1.1.1 &>/dev/null ; do sleep 1; done; for pkg in sudo openssh-server iproute rsync dnsmasq  python3 tar; do yum install -q -y $pkg ; done); chmod -R og-rwx /root/.ssh;sed -i -e '\''s/#UseDNS yes/UseDNS no/'\'' -e '\''s/#PermitRootLogin.*$/PermitRootLogin prohibit-password/'\'' /etc/ssh/sshd_config;sed '\''s@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g'\'' -i /etc/pam.d/sshd; chmod 0600 /root/.ssh/authorized_keys; chmod 0700 /root/.ssh; chown root:root -R /root/.ssh; yum install -q -y https://repo.percona.com/yum/release/7/RPMS/x86_64/libeatmydata-0.1-00.21.el7.centos.x86_64.rpm; dnf -y install openssh-server rsync python3 iproute procps-ng openssh-clients; dnf clean all; systemctl enable sshd'
lxc stop $USER-default
lxc publish $USER-default --alias rockylinux/8-sshd-systemd-$USER
lxc delete $USER-default

# Rocky9
#lxc launch --profile $USER images:rockylinux/9 $USER-default
lxc launch --profile $USER images:1a07136f41cf $USER-default
until lxc exec $USER-default true ; do sleep 1 ; done
lxc file push ../secret/id_rsa.pub $USER-default/root/authorized_keys
lxc file push ../tools/node_ip.sh $USER-default/usr/bin/node_ip.sh
lxc file push ../tools/fix_el8_ip.sh $USER-default/usr/bin/fix_el8_ip.sh

lxc exec $USER-default -- bash -c 'export LANG=C;mkdir /root/.ssh;mv /root/authorized_keys /root/.ssh;bash /usr/bin/fix_el8_ip.sh;test -f /usr/bin/rsync || (until ping  -c 1 1.1.1.1 &>/dev/null ; do sleep 1; done; for pkg in sudo openssh-server iproute rsync dnsmasq  python3 tar; do yum install -q -y $pkg ; done); chmod -R og-rwx /root/.ssh;sed -i -e '\''s/#UseDNS yes/UseDNS no/'\'' -e '\''s/#PermitRootLogin.*$/PermitRootLogin prohibit-password/'\'' /etc/ssh/sshd_config;sed '\''s@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g'\'' -i /etc/pam.d/sshd; chmod 0600 /root/.ssh/authorized_keys; chmod 0700 /root/.ssh; chown root:root -R /root/.ssh; dnf -y install openssh-server rsync python3 iproute procps-ng openssh-clients; dnf clean all; systemctl enable sshd'
lxc stop $USER-default
lxc publish $USER-default --alias rockylinux/9-sshd-systemd-$USER
lxc delete $USER-default

# Ubuntu 22.04 Jammy
lxc launch --profile $USER ubuntu:22.04 $USER-default
until lxc exec $USER-default true ; do sleep 1 ; done
lxc file push ../secret/id_rsa.pub $USER-default/root/authorized_keys
lxc file push ../tools/node_ip.sh $USER-default/usr/bin/node_ip.sh
lxc file push ../tools/fix_el8_ip.sh $USER-default/usr/bin/fix_el8_ip.sh

lxc exec $USER-default -- bash -c 'export LANG=C;mkdir /root/.ssh;mv /root/authorized_keys /root/.ssh;until ping  -c 1 1.1.1.1 &>/dev/null ; do sleep 1; done; apt update ;apt -y install openssh-server rsync python3 iproute2 openssh-client gawk; apt clean; systemctl enable ssh; chmod -R og-rwx /root/.ssh;sed -i -e '\''s/#UseDNS yes/UseDNS no/'\'' -e '\''s/#PermitRootLogin.*$/PermitRootLogin prohibit-password/'\'' /etc/ssh/sshd_config;sed '\''s@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g'\'' -i /etc/pam.d/sshd; chmod 0600 /root/.ssh/authorized_keys; chmod 0700 /root/.ssh; chown root:root -R /root/.ssh'
lxc stop $USER-default
lxc publish $USER-default --alias ubuntu/jammy-sshd-systemd-$USER
lxc delete $USER-default

