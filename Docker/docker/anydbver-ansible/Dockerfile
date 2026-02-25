# docker run -itd --privileged --name=c7 c7-systemd
FROM centos:7
MAINTAINER "Nickolay Ihalainen" ihanick@gmail.com
ENV container docker
COPY secret/id_rsa.pub /root/.ssh/authorized_keys
COPY secret/id_rsa.pub /root/.ssh/id_rsa.pub
COPY secret/id_rsa /root/.ssh/id_rsa
COPY tools/node_ip.sh /usr/bin/node_ip.sh
COPY tools/fix_el8_ip.sh /usr/bin/fix_el8_ip.sh
COPY entrypoint.sh /entrypoint.sh

RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in ; do [  == systemd-tmpfiles-setup.service ] || rm -f ; done); \
rm -f /lib/systemd/system/multi-user.target.wants/*; \
rm -f /etc/systemd/system/.wants/*; \
rm -f /lib/systemd/system/local-fs.target.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/udev; \
rm -f /lib/systemd/system/sockets.target.wants/initctl; \
rm -f /lib/systemd/system/basic.target.wants/*; \
rm -f /lib/systemd/system/anaconda.target.wants/*; \
yum install -y sudo sudo openssh-server iproute rsync ; \
chmod -R og-rwx /root/.ssh; \
sed -i -e 's/#UseDNS yes/UseDNS no/' -e 's/#PermitRootLogin.*$/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config; \
sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd; \
chmod 0600 /root/.ssh/authorized_keys; \
chmod 0700 /root/.ssh; \
chown root:root -R /root/.ssh; \
yum install -q -y https://repo.percona.com/yum/release/7/RPMS/x86_64/libeatmydata-0.1-00.21.el7.centos.x86_64.rpm; \
systemctl enable sshd; \
yum install -y epel-release; \
yum install -y openssh-clients git ansible; \
cd /root; \
git clone https://github.com/zelmario/anydbver.git; \
cd anydbver/; \
./anydbver configure provider:lxd; \
./anydbver update; \
cp -a /root/.ssh/id_rsa /root/.ssh/id_rsa.pub /root/anydbver/secret/; \
chmod +x /entrypoint.sh;
VOLUME [ "/sys/fs/cgroup" ]
CMD ["/entrypoint.sh"]
