FROM         rockylinux:8
 ENV container docker
 RUN dnf install -y epel-release; dnf -y install rsync python3 ansible; dnf clean all
 COPY anydbver.tar.gz /anydbver.tar.gz
 RUN mkdir /anydbver;tar -C /anydbver -xzf /anydbver.tar.gz
