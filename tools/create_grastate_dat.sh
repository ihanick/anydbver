#!/bin/bash
mysqld --user mysql &>/dev/null &
until mysqladmin --silent --connect-timeout=30 --wait=4 ping ; do sleep 5 ; done
mysqladmin shutdown
