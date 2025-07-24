#!/bin/bash

KEY="$HOME/.ssh/simplyblock-ohio.pem"

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --k8s-snode <value>                  Set Storage node to run on k8s (default: false)"
    echo "  --help                               Print this help message"
    exit 0
}

K8S_SNODE="false"

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
    --k8s-snode)
        K8S_SNODE="true"
        ;;
    --help)
        print_help
        ;;
    *)
        echo "Unknown option: $1"
        print_help
        ;;
    esac
    shift
done

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
    KEY="$HOME/.ssh/$KEY_NAME"
    if [ -f "$HOME/.ssh/$KEY_NAME" ]; then
        echo "the ssh key: ${KEY} already exits on local"
    else
        echo "$SECRET_VALUE" >"$KEY"
        chmod 400 "$KEY"
    fi
else
    echo "Failed to retrieve secret value. Falling back to default key."
fi

BASTION_IP=$(terraform output -raw bastion_public_ip)
mnodes=($(terraform output -raw extra_nodes_public_ips))

mnodes_private_ips=$(terraform output -raw extra_nodes_private_ips)
IFS=' ' read -ra mnodes_private_ips <<<"$mnodes_private_ips"

storage_private_ips=$(terraform output -raw storage_private_ips)
sec_storage_private_ips=$(terraform output -raw sec_storage_private_ips)

echo "KEY=$KEY" >> ${GITHUB_OUTPUT:-/dev/stdout}
echo "extra_node_ip=${mnodes[0]}" >> ${GITHUB_OUTPUT:-/dev/stdout}

detect_ssh_user() {
    local target_ip="$1"
    local bastion_ip="$2"
    local user="ec2-user"

    for u in ec2-user rocky ubuntu; do
        if ssh -i "$KEY" \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=no \
            -o ProxyCommand="ssh -i \"$KEY\" -o StrictHostKeyChecking=no -W %h:%p ec2-user@$bastion_ip" \
            $u@$target_ip "command -v bash" >/dev/null 2>&1; then
            user="$u"
            break
        fi
    done

    echo "$user"
}


read -r -d '' PKG_INSTALL_SNIPPET <<'EOF'
detect_pkg_manager() {
    if command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v apt >/dev/null 2>&1; then
        echo "apt"
    else
        echo "unknown"
    fi
}

PKG_MANAGER=$(detect_pkg_manager)

if [ "$PKG_MANAGER" = "yum" ]; then
    sudo yum install -y fio nvme-cli pciutils make golang
elif [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt update
    sudo apt install -y fio nvme-cli pciutils make golang
else
    echo "Unsupported package manager: $PKG_MANAGER"
    exit 1
fi
EOF

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
$PKG_INSTALL_SNIPPET
sudo modprobe nvme-tcp
sudo modprobe nbd
total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
total_memory_mb=\$((total_memory_kb / 1024))
hugepages=\$((total_memory_mb / 4 ))
sudo sysctl -w vm.nr_hugepages=\$hugepages
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--advertise-address=${mnodes[0]}' bash
sudo /usr/local/bin/k3s kubectl taint nodes --all node-role.kubernetes.io/master-
sudo chown ec2-user:ec2-user /etc/rancher/k3s/k3s.yaml
echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
echo 'nbd' | sudo tee /etc/modules-load.d/nbd.conf
echo \"vm.nr_hugepages=\$hugepages\" | sudo tee /etc/sysctl.d/hugepages.conf
sudo sysctl --system
"

MASTER_NODE_NAME=$(ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "kubectl get nodes -o wide | grep -w ${mnodes_private_ips[0]} | awk '{print \$1}'")
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "kubectl label nodes $MASTER_NODE_NAME type=simplyblock-cache --overwrite"

TOKEN=$(ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "sudo cat /var/lib/rancher/k3s/server/node-token")

for ((i=1; i<${#mnodes[@]}; i++)); do
    ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[${i}]} "
    $PKG_INSTALL_SNIPPET
    sudo modprobe nvme-tcp
    sudo modprobe nbd
    total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
    total_memory_mb=\$((total_memory_kb / 1024))
    hugepages=\$((total_memory_mb / 4 / 2))
    sudo sysctl -w vm.nr_hugepages=\$hugepages
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
    sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
    curl -sfL https://get.k3s.io | K3S_URL=https://${mnodes[0]}:6443 K3S_TOKEN=$TOKEN bash
    echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
    echo 'nbd' | sudo tee /etc/modules-load.d/nbd.conf
    echo \"vm.nr_hugepages=\$hugepages\" | sudo tee /etc/sysctl.d/hugepages.conf
    sudo sysctl --system
    "

    NODE_NAME=$(ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "kubectl get nodes -o wide | grep -w ${mnodes_private_ips[${i}]} | awk '{print \$1}'")
    ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "kubectl label nodes $NODE_NAME type=simplyblock-cache --overwrite"
done

if [ "$K8S_SNODE" == "true" ]; then
    for node in ${storage_private_ips[@]}; do
        echo ""
        echo "Adding primary storage node ${node}.."
        echo ""

        SSH_USER=$(detect_ssh_user "$node" "$BASTION_IP")

        ssh -i "$KEY" -o StrictHostKeyChecking=no \
            -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
            ${SSH_USER}@${node} "

            $PKG_INSTALL_SNIPPET
            sudo modprobe nvme-tcp
            sudo modprobe nbd
            total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
            total_memory_mb=\$((total_memory_kb / 1024))
            hugepages=\$((total_memory_mb / 4 / 2))
    
            sudo sysctl -w vm.nr_hugepages=\$hugepages
            sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
            sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
            sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
            curl -sfL https://get.k3s.io | K3S_URL=https://${mnodes[0]}:6443 K3S_TOKEN=$TOKEN bash
            echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
            echo 'nbd' | sudo tee /etc/modules-load.d/nbd.conf
            echo \"vm.nr_hugepages=\$hugepages\" | sudo tee /etc/sysctl.d/hugepages.conf
            sudo sysctl --system
        "

        NODE_NAME=$(ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "kubectl get nodes -o wide | grep -w ${node} | awk '{print \$1}'")
        ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "kubectl label nodes $NODE_NAME io.simplyblock.node-type=simplyblock-storage-plane --overwrite"
    done

    for node in ${sec_storage_private_ips[@]}; do
        echo ""
        echo "Adding secondary storage node ${node}.."
        echo ""

        SSH_USER=$(detect_ssh_user "$node")

        ssh -i "$KEY" -o StrictHostKeyChecking=no \
            -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
            ${SSH_USER}@${node} "

            sudo yum install -y fio nvme-cli;
            sudo modprobe nvme-tcp
            sudo modprobe nbd
            total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
            total_memory_mb=\$((total_memory_kb / 1024))
            hugepages=\$((total_memory_mb / 4 / 2))

            sudo sysctl -w vm.nr_hugepages=\$hugepages
            sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
            sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
            sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
            curl -sfL https://get.k3s.io | K3S_URL=https://${mnodes[0]}:6443 K3S_TOKEN=$TOKEN bash
            sudo yum install -y pciutils
            lspci
            sudo yum install -y make golang
            echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
            echo 'nbd' | sudo tee /etc/modules-load.d/nbd.conf
            echo \"vm.nr_hugepages=\$hugepages\" | sudo tee /etc/sysctl.d/hugepages.conf
            sudo sysctl --system
        "

        NODE_NAME=$(ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "kubectl get nodes -o wide | grep -w ${node} | awk '{print \$1}'")
        ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "kubectl label nodes $NODE_NAME io.simplyblock.node-type=simplyblock-storage-plane-reserve --overwrite"
    done
fi
