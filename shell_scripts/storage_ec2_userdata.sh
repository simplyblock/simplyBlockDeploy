#!/bin/bash
sudo sysctl -w vm.nr_hugepages=2048
echo "vm.nr_hugepages=2048" | sudo tee -a /etc/sysctl.conf
