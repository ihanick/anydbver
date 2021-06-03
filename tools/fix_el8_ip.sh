#!/bin/bash
grep -q 'PLATFORM_ID="platform:el8"' /etc/os-release || exit 0
systemctl status NetworkManager|grep -q 'NetworkManager.service; enabled' || exit 0
until nmcli &>/dev/null ; do sleep 1; done
until systemctl status dbus.service|grep -q -F 'active (running)' ; do sleep 1 ; done
ifup eth0
nmcli -t d show eth0|grep -q unmanaged || exit 0
ip -4 addr ls dev eth0|grep -q inet && exit 0
pgrep dhclient &>/dev/null && exit 0
dhclient eth0
