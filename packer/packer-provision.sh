#!/usr/bin/env bash

set -e

sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum update -y
sudo yum install -y pip fio nvme-cli yum-utils xorg-x11-xauth nvme-cli fio hostname pkg-config git wget python3-pip yum-utils docker-ce docker-ce-cli \
  containerd.io docker-buildx-plugin docker-compose-plugin
sudo modprobe nvme-tcp
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
