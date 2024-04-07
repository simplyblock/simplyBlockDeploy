#!/bin/bash

KEY="$HOME/.ssh/simplyblock-ohio.pem"

SECRET_VALUE=$(terraform output -raw secret_value)
KEY_NAME=$(terraform output -raw key_name)

ssh_dir="$HOME/.ssh"

if [ ! -d "$ssh_dir" ]; then
    mkdir -p "$ssh_dir"
    echo "Directory $ssh_dir created."
else
    echo "Directory $ssh_dir already exists."
fi

if [[ -n "$SECRET_VALUE" ]]; then
    rm "$HOME/.ssh/$KEY_NAME"
    echo "$SECRET_VALUE" > "$HOME/.ssh/$KEY_NAME"
    KEY="$HOME/.ssh/$KEY_NAME"
    chmod 400 "$KEY"
else
    echo "Failed to retrieve secret value. Falling back to default key."
fi

mnodes=($(terraform output -raw extra_nodes_public_ips))

echo "::set-output name=KEY::$KEY"
echo "::set-output name=extra_node_ip::${mnodes[0]}"

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
sudo yum install -y fio nvme-cli;
sudo modprobe nvme-tcp
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--advertise-address=${mnodes[0]}' bash
sudo /usr/local/bin/k3s kubectl get node
sudo sysctl -w vm.nr_hugepages=4096
sudo systemctl restart k3s
sudo yum install -y pciutils
lspci
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
"
