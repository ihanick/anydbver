FROM centos:centos7
 ENV container docker
 RUN yum -y install openssh-server rsync python3 iproute procps-ng openssh-clients; yum clean all; systemctl enable sshd
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
 ;do systemctl mask $service; done; rm -f /usr/lib/tmpfiles.d/systemd-nologin.conf
 COPY node_ip.sh /usr/bin/node_ip.sh
 COPY rc.local /etc/rc.local
 COPY rc-local.service /etc/systemd/system/rc-local.service
 RUN chown root:root /etc/rc.local; chmod 0755 /etc/rc.local ; systemctl enable rc-local
 VOLUME [ "/sys/fs/cgroup" ]
 CMD [ "/usr/lib/systemd/systemd", "--system", "--unit=multi-user.target", "--log-target=console", "--log-level=debug", "--show-status=true" ]
