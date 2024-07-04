FROM centos:centos7
 ENV container docker
 RUN sed -i -e 's/mirror.centos.org/vault.centos.org/g' -e 's/^#.*baseurl=http/baseurl=http/g' -e 's/^mirrorlist=http/#mirrorlist=http/g'   /etc/yum.repos.d/CentOS-*.repo ; \
  if uname -m | grep x86_64 ; then curl -LO  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 ; chmod +x yq_linux_amd64; mv yq_linux_amd64 /usr/local/bin/yq ; \
  else curl -LO  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64 ; chmod +x yq_linux_arm64; mv yq_linux_arm64 /usr/local/bin/yq ; fi ; \
  yum -y install openssh-server rsync python3 iproute procps-ng openssh-clients; yum clean all; systemctl enable sshd
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
