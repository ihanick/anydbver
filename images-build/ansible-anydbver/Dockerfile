FROM         rockylinux:8
ENV container docker
RUN dnf install -y epel-release; dnf -y install rsync python3 ansible openssh-clients;ansible-galaxy collection install theredgreek.sqlite; \
  if uname -m | grep x86_64 ; then curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl ; \
  else curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl ; fi ; \
  chmod +x kubectl ; \
  mv kubectl /usr/local/bin/kubectl; \
  if uname -m | grep x86_64 ; then curl -LO  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 ; chmod +x yq_linux_amd64; mv yq_linux_amd64 /usr/local/bin/yq ; \
  else curl -LO  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64 ; chmod +x yq_linux_arm64; mv yq_linux_arm64 /usr/local/bin/yq ; fi ; \
  dnf clean all
ADD anydbver.tar.gz /vagrant/
