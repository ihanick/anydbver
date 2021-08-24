#!/bin/bash
grep -q 'PLATFORM_ID="platform:el8"' /etc/os-release || exit 0
until dbus-send --system --print-reply  --dest=org.freedesktop.systemd1 \
  /org/freedesktop/systemd1 org.freedesktop.DBus.Properties.Get string:'org.freedesktop.systemd1.Manager' string:'Version' ; do sleep 1; done
systemctl status NetworkManager|grep -q 'NetworkManager.service; enabled' || exit 0
until dbus-send --system --print-reply --dest=org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.DBus.Properties.Get string:"org.freedesktop.NetworkManager" string:"ActiveConnections" ; do sleep 1; done
ifup eth0
nmcli -t d show eth0|grep -q unmanaged || exit 0
ip -4 addr ls dev eth0|grep -q inet && exit 0
pgrep dhclient &>/dev/null && exit 0
dhclient eth0
