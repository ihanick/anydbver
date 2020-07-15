# docker build -t centos:8-systemd .
FROM centos:8
RUN yum install -y systemd sudo openssh-server iproute rsync python3; \
  yum clean all
