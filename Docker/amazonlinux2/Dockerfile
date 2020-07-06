# docker build -t amazonlinux:2-systemd .
FROM amazonlinux:2
RUN yum install -y systemd sudo openssh-server iproute rsync; \
  yum clean all
