FROM         centos/systemd
 RUN yum -y install openssh-server rsync python3 iproute procps-ng openssh-clients; yum clean all; systemctl enable sshd
 EXPOSE 22
 RUN for service in\
 console-getty.service\
 dbus.service\
 dbus.socket\
 dev-hugepages.mount\
 getty.target\
 sys-fs-fuse-connections.mount\
 systemd-logind.service\
 systemd-remount-fs.service\
 systemd-udevd\
 systemd-vconsole-setup.service\
 ;do systemctl mask $service; done; rm -f /usr/lib/tmpfiles.d/systemd-nologin.conf; mkdir /root/.ssh
 COPY node_ip.sh /usr/bin/node_ip.sh
 COPY id_rsa.pub /root/.ssh/authorized_keys
 VOLUME [ "/sys/fs/cgroup" ]
 CMD [ "/usr/lib/systemd/systemd", "--system", "--unit=multi-user.target", "--log-target=console", "--log-level=debug", "--show-status=true" ]
