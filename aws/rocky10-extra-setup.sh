#!/bin/bash

set -exo pipefail


storage_private_ips=$(terraform output -raw storage_private_ips)
BASTION_IP=$(terraform output -raw bastion_public_ip)
KEY="${KEY:-$HOME/.ssh/id_ed25519}"

for node in $storage_private_ips; do
    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@$BASTION_IP" rocky@$node "sudo reboot"
done

for node in $storage_private_ips; do
    echo "Waiting for $node to come back online..."
    while ! ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@$BASTION_IP" rocky@$node "true"; do
        sleep 5
    done
done

for node in $storage_private_ips; do
    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@$BASTION_IP" rocky@$node "
                total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
                total_memory_mb=\$((total_memory_kb / 1024))
                hugepages=\$((total_memory_mb / 4 / 2))
                sudo sysctl -w vm.nr_hugepages=\$hugepages
                sudo systemctl restart k3s-agent
        "
done
