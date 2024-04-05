#!/bin/zsh

KEY=$HOME/.ssh/simplyblock-ohio.pem

mnodes=($(terraform output -raw extra_nodes_public_ips))


ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[1] "
sudo yum install -y fio nvme-cli;
sudo modprobe nvme-tcp
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--advertise-address=$mnodes[1]' bash
sudo /usr/local/bin/k3s kubectl get node
sudo sysctl -w vm.nr_hugepages=4096
sudo systemctl restart k3s
sudo chown ec2-user:ec2-user /etc/rancher/k3s/k3s.yaml
sudo yum install -y make golang
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker

nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
for node in $nodes; do
    kubectl label nodes $node type=cache
done
EXTRA_NODE_IP=${mnodes[1]}
echo "::set-output name=extra_node_ip::$EXTRA_NODE_IP"

sudo cat /etc/rancher/k3s/k3s.yaml
"
