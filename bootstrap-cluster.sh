#!/bin/bash

KEY="$HOME/.ssh/simplyblock-ohio.pem"

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --memory <value>                     Set SPDK huge memory allocation"
    echo "  --cpu-mask <value>                   Set SPDK app CPU mask"
    echo "  --iobuf_small_pool_count <value>     Set bdev_set_options param"
    echo "  --iobuf_large_pool_count <value>     Set bdev_set_options param"
    echo "  --help                               Print this help message"
    exit 0
}

MEMORY=""
CPU_MASK=""
IOBUF_SMALL_POOL_COUNT=""
IOBUF_LARGE_POOL_COUNT=""

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        --memory)
            MEMORY="$2"
            shift
            ;;
        --cpu-mask)
            CPU_MASK="$2"
            shift
            ;;
        --iobuf_small_pool_count)
            IOBUF_SMALL_POOL_COUNT="$2"
            shift
            ;;
        --iobuf_large_pool_count)
            IOBUF_LARGE_POOL_COUNT="$2"
            shift
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
    rm "$HOME/.ssh/$KEY_NAME"
    echo "$SECRET_VALUE" > "$HOME/.ssh/$KEY_NAME"
    KEY="$HOME/.ssh/$KEY_NAME"
    chmod 400 "$KEY"
else
    echo "Failed to retrieve secret value. Falling back to default key."
fi

mnodes=$(terraform output -raw mgmt_public_ips)
storage_private_ips=$(terraform output -raw storage_private_ips)
storage_public_ips=$(terraform output -raw storage_public_ips)

echo "bootstrapping cluster..."

while true; do
    echo "mgmt_public_ips: ${mnodes[0]}"
    dstatus=$(ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "sudo cloud-init status" 2>/dev/null)
    echo "Current status: $dstatus"

    if [[ "$dstatus" == "status: done" ]]; then
        echo "Cloud-init is done. Exiting loop."
        break
    fi

    echo "Waiting for cloud-init to finish..."
    sleep 10
done

echo ""
echo "Deploying management node..."
echo ""

# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
sbcli-mig cluster create
"

echo ""
echo "Adding other management nodes if they exist.."
echo ""

for ((i = 2; i <= $#mnodes; i++)); do
    echo ""
    echo "Adding mgmt node ${i}.."
    echo ""

    ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[${i}]} "
    MANGEMENT_NODE_IP=${mnodes[0]}
    CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
    echo \"Cluster ID is: \${CLUSTER_ID}\"
    sbcli-mig mgmt add \${MANGEMENT_NODE_IP} \${CLUSTER_ID} eth0
    "
done

storage_public_ip=$(echo ${storage_public_ips} | cut -d' ' -f1)

DEVICE_ID=$(ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@${storage_public_ip} "
desired_size_bytes=2147483648  # 2 GB in bytes
device_name=\$(lsblk -b -o NAME,SIZE | grep -w "\$desired_size_bytes" | awk '{print \$1}')
if [ -n "\$device_name" ]; then
    device_id=\$(udevadm info --query=property --name="/dev/\$device_name" | grep ID_PATH= | awk -F'[:-]' '{print \$3 \".\" \$4}')
    echo "\$device_id"
    exit 0
fi
echo "No matching device found."
exit 1
")

echo "$DEVICE_ID"

echo ""
sleep 60
echo "Adding storage nodes..."
echo ""
# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \"Cluster ID is: \${CLUSTER_ID}\"
sbcli-mig cluster unsuspend \${CLUSTER_ID}

for node in ${storage_private_ips}; do
    echo ""
    echo "joining node \${node}"
    sbcli-mig storage-node add-node \
        --jm-pcie "$DEVICE_ID" \
        --memory "$MEMORY" \
        --cpu-mask "$CPU_MASK" \
        --iobuf_small_pool_count "$IOBUF_SMALL_POOL_COUNT" \
        --iobuf_large_pool_count "$IOBUF_LARGE_POOL_COUNT" \
        \$CLUSTER_ID \${node}:5000 eth0
    sleep 5
done
"

echo ""
echo "getting cluster id"
echo ""

CLUSTER_ID=$(ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \${CLUSTER_ID}
")

echo ""
echo "getting cluster secret"
echo ""

CLUSTER_SECRET=$(ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
sbcli-mig cluster get-secret \${CLUSTER_ID}
")

echo ""
echo "adding pool testing1"
echo ""

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
sbcli-mig pool add testing1
"

echo "::set-output name=cluster_id::$CLUSTER_ID"
echo "::set-output name=cluster_secret::$CLUSTER_SECRET"
echo "::set-output name=cluster_ip::${mnodes[0]}"

echo ""
echo "Successfully deployed the cluster"
echo ""
