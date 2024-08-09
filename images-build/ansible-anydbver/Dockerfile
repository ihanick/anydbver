FROM         rockylinux:8
ENV container docker
ADD anydbver.tar.gz /vagrant/
RUN dnf install -y epel-release; dnf -y install rsync python3 ansible openssh-clients;ansible-galaxy collection install theredgreek.sqlite; \
  if uname -m | grep x86_64 ; then curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl ; \
  curl -sL https://get.helm.sh/helm-v3.15.3-linux-amd64.tar.gz | tar --strip-components=1 -C /usr/local/bin -xz linux-amd64/helm ; \
  else curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl ; \
  curl -sL https://get.helm.sh/helm-v3.15.3-linux-arm64.tar.gz | tar --strip-components=1 -C /usr/local/bin -xz linux-arm64/helm ; \
  fi ; \
  chmod +x kubectl ; \
  mv kubectl /usr/local/bin/kubectl; \
  if uname -m | grep x86_64 ; \
    then curl -LO  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 ; \
    chmod +x yq_linux_amd64; mv yq_linux_amd64 /usr/local/bin/yq ; \
  else curl -LO  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64 ; \
    chmod +x yq_linux_arm64; mv yq_linux_arm64 /usr/local/bin/yq; \
  fi ; \
  cp /usr/local/bin/yq /vagrant/tools/yq ; \
  dnf clean all
