#!/bin/bash
PASSWORD=$2

ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/ppolicy.ldif
ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulePath: /usr/lib64/openldap
olcModuleLoad: ppolicy.la
EOF
ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=ppolicy,olcDatabase={2}hdb,cn=config
objectClass: olcPPolicyConfig
olcPPolicyDefault: cn=ppolicy,ou=policies,dc=percona,dc=local
EOF

ldapadd -x -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local"  <<EOF
dn: ou=policies,dc=percona,dc=local
objectClass: top
objectClass: organizationalUnit
ou: policies
EOF

ldapadd -x -w $PASSWORD -D "cn=ldapadm,dc=percona,dc=local"  <<EOF
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
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: to attrs=userPassword by self write by anonymous auth by dn.base="cn=ldapadm,dc=percona,dc=local" write by * none
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: to * by self write by dn.base="cn=ldapadm,dc=percona,dc=local" write by * read
EOF
