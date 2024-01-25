#!/bin/bash


mnodes=(18.220.65.180 18.118.86.135 3.15.33.167)
mnodesp=(10.0.4.72 10.0.4.88 10.0.4.139)

# simplified
sudo yum install -y fio nvme-cli;
sudo modprobe nvme-tcp
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
curl -sfL https://get.k3s.io | bash
sudo /usr/local/bin/k3s kubectl get node
sudo chown ec2-user:ec2-user /etc/rancher/k3s/k3s.yaml
sudo yum install -y make golang
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker


KEY=$HOME/.ssh/simplyblock-ohio.pem
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[1] "
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--advertise-address=$mnodes[1] --flannel-backend=none --disable-network-policy --cluster-cidr=192.168.0.0/16' sh -
sudo /usr/local/bin/k3s kubectl get node
"

sudo chown ec2-user:ec2-user /etc/rancher/k3s/k3s.yaml

NODE_TOKEN=$(ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[1] "
sudo cat /var/lib/rancher/k3s/server/node-token
")

echo "token is ${NODE_TOKEN}"

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[2] "
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
curl -sfL https://get.k3s.io | K3S_URL=https://${mnodesp[1]}:6443 K3S_TOKEN=${NODE_TOKEN} sh -
sudo /usr/local/bin/k3s kubectl get node
"

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[3] "
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
curl -sfL https://get.k3s.io | K3S_URL=https://${mnodesp[1]}:6443 K3S_TOKEN=${NODE_TOKEN} sh -
sudo /usr/local/bin/k3s kubectl get node
"


### enable huge pages


sudo echo "vm.nr_hugepages=2048" >> /etc/sysctl.conf
sudo sysctl -p

# in the file /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash hugepagesz=2M hugepages=1024"

# update grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

sudo reboot

# reboot conform the huge pages

sudo nvme list-subsys <device>
