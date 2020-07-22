#!/bin/bash
export PATH=/opt/samba/bin:/opt/samba/sbin:$PATH
samba-tool domain provision --realm PERCONA.LOCAL --domain PERCONA --adminpass=verysecret123^
ln -s /opt/samba/private/krb5.conf /etc
systemctl start samba.service

samba-tool group add support
samba-tool group add dba
samba-tool group add search

samba-tool user create mysqldba verysecretpassword1^
samba-tool user create nihalainen verysecretpassword1^
samba-tool user create ldap verysecretpassword1^

samba-tool group addmembers support nihalainen
samba-tool group addmembers dba mysqldba
samba-tool group addmembers search ldap

touch /root/samba.configured
