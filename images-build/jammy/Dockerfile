FROM         ubuntu:jammy
 ENV container docker
 RUN apt update ;apt -y install openssh-server rsync python3 iproute2 openssh-client gawk; apt clean; systemctl enable ssh
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
 systemd-networkd.socket \
 systemd-networkd \
 networkd-dispatcher \
 systemd-networkd-wait-online \
 ;do systemctl mask $service; done; mkdir /root/.ssh
 COPY node_ip.sh /usr/bin/node_ip.sh
 COPY id_rsa.pub /root/.ssh/authorized_keys
 VOLUME [ "/sys/fs/cgroup" ]
 #RUN chattr +C /var/log/journal
 #ADD install/journald.conf /etc/systemd/journald.conf
 #ADD install/system.conf   /etc/systemd/system.conf
 CMD [ "/usr/lib/systemd/systemd", "--system", "--unit=multi-user.target", "--log-target=console", "--log-level=debug", "--show-status=true" ]
