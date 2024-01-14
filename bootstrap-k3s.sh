#!/bin/bash


mnodes=(18.220.65.180 18.118.86.135 3.15.33.167)
mnodesp=(10.0.4.72 10.0.4.88 10.0.4.139)

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
