FROM         rockylinux:8
ENV container docker
ADD anydbver.tar.gz /vagrant/
RUN dnf install -y epel-release; dnf -y install rsync python3 ansible openssh-clients which;ansible-galaxy collection install theredgreek.sqlite; \
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
  curl https://sdk.cloud.google.com > install.sh ; bash install.sh --disable-prompts --install-dir=/opt ; \
  echo source /opt/google-cloud-sdk/completion.bash.inc >> ~/.bashrc ; \
  echo source /opt/google-cloud-sdk/path.bash.inc >> ~/.bashrc ; \
  echo 'source <(kubectl completion bash)' >> ~/.bashrc ; \
  echo 'source <(helm completion bash)' >> ~/.bashrc ; \
  echo 'export HELM_CACHE_HOME=/vagrant/data/helm/cache HELM_CONFIG_HOME=/vagrant/data/helm/config HELM_DATA_HOME=/vagrant/data/helm/data' >> ~/.bashrc ; \
  source ~/.bashrc ; gcloud components install --quiet gke-gcloud-auth-plugin ; \
  dnf clean all
