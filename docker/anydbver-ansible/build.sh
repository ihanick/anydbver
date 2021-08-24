#!/bin/bash
cd $(dirname "$0")
docker build --rm -t c7-anydbver-ansible .
