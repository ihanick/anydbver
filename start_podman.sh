#!/bin/bash
test -f secret/id_rsa || ssh-keygen -t rsa -f secret/id_rsa -P '' && chmod 0600 secret/id_rsa

:> ansible_hosts
for i in ${USER}.default $(seq 1 2|sed -e s/^/${USER}.node/); do
  #sudo podman run -d --security-opt label=type:spc_t --security-opt seccomp=unconfined --name $i centos:7 /sbin/init
  sudo podman run -d --name $i centos:7 /sbin/init
  sudo podman cp $PWD/secret/id_rsa.pub $i:/root/.ssh/authorized_keys
  sudo podman cp $PWD/tools/node_ip.sh $i:/usr/bin/node_ip.sh
  sudo podman exec $i bash -c "yum install -y sudo openssh-server iproute rsync; chmod -R og-rwx /root/.ssh;sed -i -e 's/#UseDNS yes/UseDNS no/' -e 's/#PermitRootLogin.*$/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config;sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd;systemctl enable sshd;systemctl restart sshd"

  IP=$(sudo podman exec $i /bin/bash /usr/bin/node_ip.sh)
  #echo "$i ansible_connection=podman ansible_python_interpreter=/usr/bin/python2.7" >> ansible_hosts
  echo "$i ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host=$IP ansible_python_interpreter=/usr/bin/python2.7 ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> ansible_hosts
done
