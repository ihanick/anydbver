FROM         rockylinux:9
 ENV container docker
 RUN dnf -y install openssh-server rsync python3 iproute procps-ng openssh-clients; dnf clean all; systemctl enable sshd
 STOPSIGNAL SIGRTMIN+3
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
 dnf-makecache.timer\
 ;do systemctl mask $service; done; mkdir /root/.ssh
 COPY node_ip.sh /usr/bin/node_ip.sh
 COPY id_rsa.pub /root/.ssh/authorized_keys
 VOLUME [ "/sys/fs/cgroup" ]
 #RUN chattr +C /var/log/journal
 #ADD install/journald.conf /etc/systemd/journald.conf
 #ADD install/system.conf   /etc/systemd/system.conf
 CMD [ "/usr/lib/systemd/systemd", "--system", "--unit=multi-user.target", "--log-target=console", "--log-level=debug", "--show-status=true" ]