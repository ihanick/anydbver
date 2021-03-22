#!/bin/bash

USR="$1"
LDAP_PASS="$2"
DOM="$3"

apt-get install -y debconf-utils

debconf-set-selections <<EOF
slapd slapd/password2 password $LDAP_PASS
slapd slapd/password1 password $LDAP_PASS
slapd slapd/internal/adminpw password $LDAP_PASS
slapd slapd/internal/generated_adminpw password $LDAP_PASS
slapd slapd/domain string $DOM
slapd shared/organization string $DOM
EOF

