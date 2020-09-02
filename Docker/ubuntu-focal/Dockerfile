# docker build -t ubuntu:focal-systemd .
FROM ubuntu:focal
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y systemd sudo openssh-server iproute2 rsync python3 \
  && rm -rf /var/lib/apt/lists/*
