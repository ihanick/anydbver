# cp ../../tools/install_samba_ad.sh ./; sudo podman build -t centos:7-samba .
FROM centos:7
RUN yum install -y systemd sudo openssh-server iproute rsync; \
  yum clean all
COPY install_samba_ad.sh /root/install_samba_ad.sh
RUN /bin/bash /root/install_samba_ad.sh
