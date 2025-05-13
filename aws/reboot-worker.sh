#!/bin/bash
set -euo pipefail

KEY="$HOME/.ssh/simplyblock-ohio.pem"

SECRET_VALUE=$(terraform output -raw secret_value)
KEY_NAME=$(terraform output -raw key_name)
BASTION_IP=$(terraform output -raw bastion_public_ip)
GRAFANA_ENDPOINT=$(terraform output -raw grafana_invoke_url)

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

storage_private_ips=$(terraform output -raw storage_private_ips)

echo "rebooting k3s workers..."

for node in ${storage_private_ips}; do
    echo ""
    echo "rebooting worker node ${node}.."
    echo ""

    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
        ec2-user@${node} "
    sudo reboot
    "
done

sleep 5

echo "workers reboot completed..."
