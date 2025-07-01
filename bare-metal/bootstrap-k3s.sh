#!/bin/bash

KEY="$HOME/.ssh/simplyblock-us-east-2.pem"

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



IFS=' ' read -ra mnodes_private_ips <<<"$mnodes_private_ips"
BASTION_IP=$BASTION_IP
mnodes=$K3S_MNODES
echo "mgmt_private_ips: ${mnodes}"
IFS=' ' read -ra mnodes <<<"$mnodes"
storage_private_ips=$STORAGE_PRIVATE_IPS
sec_storage_private_ips=$SEC_STORAGE_PRIVATE_IPS

echo "KEY=$KEY" >> ${GITHUB_OUTPUT:-/dev/stdout}
echo "extra_node_ip=${mnodes[0]}" >> ${GITHUB_OUTPUT:-/dev/stdout}


echo "cleaning up old K8s cluster..."



# for node_ip in ${mnodes[@]}; do
#     echo "SSH into $node_ip and executing commands"
#     ssh -i "$KEY" -o StrictHostKeyChecking=no \
#         -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
#         root@${node_ip} "
#         if command -v k3s &>/dev/null; then
#             echo "Uninstalling k3s..."
#             /usr/local/bin/k3s-uninstall.sh
#         fi

#         # Remove installed packages
#         echo "Removing installed packages..."
#         sudo yum remove -y fio nvme-cli make golang

#         sleep 10 
#     "
# done

# for node_ip in ${storage_private_ips}; do
#     echo "SSH into $node_ip and executing commands"
#     ssh -i "$KEY" -o StrictHostKeyChecking=no \
#         -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
#         root@${node_ip} "
#         if command -v k3s &>/dev/null; then
#             echo "Uninstalling k3s..."
#             /usr/local/bin/k3s-uninstall.sh
#         fi

#         # Remove installed packages
#         echo "Removing installed packages..."
#         sudo yum remove -y fio nvme-cli make golang

#         sleep 10 
#     "
# done

# for node_ip in ${sec_storage_private_ips}; do
#     echo "SSH into $node_ip and executing commands"
#     ssh -i "$KEY" -o StrictHostKeyChecking=no \
#         -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
#         root@${node_ip} "
#         if command -v k3s &>/dev/null; then
#             echo "Uninstalling k3s..."
#             /usr/local/bin/k3s-uninstall.sh
#         fi

#         # Remove installed packages
#         echo "Removing installed packages..."
#         sudo yum remove -y fio nvme-cli make golang

#         sleep 10 
#     "
# done

echo "bootstrapping k3s cluster..."

ssh -i $KEY -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i $KEY -W %h:%p root@${BASTION_IP}" \
    root@${mnodes[0]} "
sudo yum install -y fio nvme-cli bc;
sudo modprobe nvme-tcp
sudo modprobe nbd
total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
total_memory_mb=\$((total_memory_kb / 1024))
#hugepages=\$(echo \"\$total_memory_mb * 0.3 / 1\" | bc)
hugepages=0

sudo sysctl -w vm.nr_hugepages=\$hugepages
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--advertise-address=${mnodes[0]} --disable=traefik' bash
sudo /usr/local/bin/k3s kubectl taint nodes --all node-role.kubernetes.io/master-
sudo /usr/local/bin/k3s kubectl get node
sudo yum install -y pciutils
lspci
sudo chown root:root /etc/rancher/k3s/k3s.yaml
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo sed -i "s/127.0.0.1/${mnodes[0]}/g" ~/.kube/config
sudo yum install -y make golang
echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
echo 'nbd' | sudo tee /etc/modules-load.d/nbd.conf
echo \"vm.nr_hugepages=\$hugepages\" | sudo tee /etc/sysctl.d/hugepages.conf
sudo sysctl --system
"

MASTER_NODE_NAME=$(ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[0]} "kubectl get nodes -o wide | grep -w ${mnodes[0]} | awk '{print \$1}'")
ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[0]} "kubectl label nodes $MASTER_NODE_NAME type=simplyblock-cache --overwrite"

TOKEN=$(ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[0]} "sudo cat /var/lib/rancher/k3s/server/node-token")

for ((i=1; i<${#mnodes[@]}; i++)); do
    ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[${i}]} "
    sudo yum install -y fio nvme-cli bc;
    sudo modprobe nvme-tcp
    sudo modprobe nbd
    total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
    total_memory_mb=\$((total_memory_kb / 1024))
    #hugepages=\$(echo \"\$total_memory_mb * 0.3 / 1\" | bc)
    hugepages=0

    sudo sysctl -w vm.nr_hugepages=\$hugepages
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
    sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
    curl -sfL https://get.k3s.io | K3S_URL=https://${mnodes[0]}:6443 K3S_TOKEN=$TOKEN bash
    sudo /usr/local/bin/k3s kubectl get node
 
    sudo yum install -y pciutils
    lspci
    sudo yum install -y make golang
    echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
    echo 'nbd' | sudo tee /etc/modules-load.d/nbd.conf
    echo \"vm.nr_hugepages=\$hugepages\" | sudo tee /etc/sysctl.d/hugepages.conf
    sudo sysctl --system
    "

    NODE_NAME=$(ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[0]} "kubectl get nodes -o wide | grep -w ${mnodes[${i}]} | awk '{print \$1}'")
    ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[0]} "kubectl label nodes $NODE_NAME type=simplyblock-cache --overwrite"
done

if [ "$K8S_SNODE" == "true" ]; then
    for node in ${storage_private_ips[@]}; do
        echo ""
        echo "Adding primary storage node ${node}.."
        echo ""

        ssh -i "$KEY" -o StrictHostKeyChecking=no \
            -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
            root@${node} "
            sudo yum install -y fio nvme-cli bc;
            sudo modprobe nvme-tcp
            sudo modprobe nbd
            total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')

            total_memory_mb=\$((total_memory_kb / 1024))
            hugepages=\$(echo \"\$total_memory_mb * 0.3 / 1\" | bc)

            sudo sysctl -w vm.nr_hugepages=\$hugepages
            sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
            sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
            sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
            curl -sfL https://get.k3s.io | K3S_URL=https://${mnodes[0]}:6443 K3S_TOKEN=$TOKEN bash
            sudo /usr/local/bin/k3s kubectl get node
            sudo yum install -y pciutils
            lspci
            sudo yum install -y make golang
            echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
            echo 'nbd' | sudo tee /etc/modules-load.d/nbd.conf
            echo \"vm.nr_hugepages=\$hugepages\" | sudo tee /etc/sysctl.d/hugepages.conf
            sudo sysctl --system
        "

        NODE_NAME=$(ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[0]} "kubectl get nodes -o wide | grep -w ${node} | awk '{print \$1}'")
        ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[0]} "kubectl label nodes $NODE_NAME type=simplyblock-storage-plane --overwrite"
    done

    for node in ${sec_storage_private_ips[@]}; do
        echo ""
        echo "Adding secondary storage node ${node}.."
        echo ""

        ssh -i "$KEY" -o StrictHostKeyChecking=no \
            -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
            root@${node} "
            sudo yum install -y fio nvme-cli bc;
            sudo modprobe nvme-tcp
            sudo modprobe nbd
            total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
            total_memory_mb=\$((total_memory_kb / 1024))
            hugepages=\$(echo \"\$total_memory_mb * 0.3 / 1\" | bc)

            sudo sysctl -w vm.nr_hugepages=\$hugepages
            sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
            sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
            sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
            curl -sfL https://get.k3s.io | K3S_URL=https://${mnodes[0]}:6443 K3S_TOKEN=$TOKEN bash
            sudo /usr/local/bin/k3s kubectl get node
            sudo yum install -y pciutils
            lspci
            sudo yum install -y make golang
            echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
            echo 'nbd' | sudo tee /etc/modules-load.d/nbd.conf
            echo \"vm.nr_hugepages=\$hugepages\" | sudo tee /etc/sysctl.d/hugepages.conf
            sudo sysctl --system
        "

        NODE_NAME=$(ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[0]} "kubectl get nodes -o wide | grep -w ${node} | awk '{print \$1}'")
        ssh -i $KEY -o StrictHostKeyChecking=no root@${mnodes[0]} "kubectl label nodes $NODE_NAME type=simplyblock-storage-plane-reserve --overwrite"
    done
fi
