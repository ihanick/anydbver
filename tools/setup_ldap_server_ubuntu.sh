#!/bin/bash
USR="$1"
PASSWORD="$2"

ldapadd -x -w $PASSWORD -D "cn=admin,dc=percona,dc=local"  <<EOF
dn: ou=People,dc=percona,dc=local
objectClass: organizationalUnit
ou: People

dn: ou=Group,dc=percona,dc=local
objectClass: organizationalUnit
ou: Group

dn: uid=dba,ou=People,dc=percona,dc=local
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
cn: dba
uid: dba
uidNumber: 9999
gidNumber: 100
homeDirectory: /home/dba
loginShell: /bin/bash
gecos: DBA [info (at) example]
userPassword: {crypt}x
shadowLastChange: 17058
shadowMin: 0
shadowMax: 99999
shadowWarning: 7
EOF

ldappasswd -s secret -w secret -D "cn=admin,dc=percona,dc=local" -x "uid=dba,ou=People,dc=percona,dc=local"
 
ldapadd -Y EXTERNAL -H ldapi:/// -f  /etc/ldap/schema/ppolicy.ldif
ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulePath: /usr/lib/ldap
olcModuleLoad: ppolicy.la
EOF

ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=ppolicy,olcDatabase={1}mdb,cn=config
objectClass: olcPPolicyConfig
olcPPolicyDefault: cn=ppolicy,ou=policies,dc=percona,dc=local
EOF

ldapadd -x -w $PASSWORD -D "cn=admin,dc=percona,dc=local"  <<EOF
dn: ou=policies,dc=percona,dc=local
objectClass: top
objectClass: organizationalUnit
ou: policies
EOF

ldapadd -x -w $PASSWORD -D "cn=admin,dc=percona,dc=local"  <<EOF
dn: cn=ppolicy,ou=policies,dc=percona,dc=local
cn: ppolicy
objectClass: top
objectClass: device
objectClass: pwdPolicy
objectClass: pwdPolicyChecker
pwdAttribute: userPassword
pwdInHistory: 8
pwdMinLength: 8
pwdMaxFailure: 3
pwdFailureCountInterval: 1800
pwdCheckQuality: 2
pwdMustChange: TRUE
pwdGraceAuthNLimit: 0
pwdMaxAge: 7776000
pwdExpireWarning: 1209600
pwdLockoutDuration: 900
pwdLockout: TRUE
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: to attrs=userPassword by self write by anonymous auth by dn.base="cn=admin,dc=percona,dc=local" write by * none
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: to * by self write by dn.base="cn=admin,dc=percona,dc=local" write by * read
EOF
