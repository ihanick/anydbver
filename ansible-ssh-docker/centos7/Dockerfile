FROM         centos/systemd
 RUN yum -y install openssh-server rsync python3 iproute procps-ng; yum clean all; systemctl enable sshd
 EXPOSE 22
 RUN mkdir /root/.ssh
 COPY node_ip.sh /usr/bin/node_ip.sh
 COPY id_rsa.pub /root/.ssh/authorized_keys
 VOLUME [ "/sys/fs/cgroup" ]
 CMD [ "/usr/lib/systemd/systemd", "--system", "--unit=multi-user.target", "--log-target=console", "--log-level=debug", "--show-status=true" ]
