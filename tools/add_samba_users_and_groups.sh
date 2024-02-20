#!/bin/sh
until samba-tool user list|grep -q Administrator ; do sleep 1 ; done
samba-tool group add support
samba-tool group add dba
samba-tool group add search

samba-tool user create mysqldba verysecretpassword1^
samba-tool user create nihalainen verysecretpassword1^
samba-tool user create ldap verysecretpassword1^

samba-tool group addmembers support nihalainen
samba-tool group addmembers dba mysqldba
samba-tool group addmembers search ldap
