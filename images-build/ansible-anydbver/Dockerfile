FROM         rockylinux:8
ENV container docker
RUN dnf install -y epel-release; dnf -y install rsync python3 ansible openssh-clients; dnf clean all
ADD anydbver.tar.gz /anydbver/
