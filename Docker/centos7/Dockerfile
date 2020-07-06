# docker build -t centos:7-systemd .
FROM centos:7
RUN yum install -y systemd sudo openssh-server iproute rsync; \
  yum clean all
