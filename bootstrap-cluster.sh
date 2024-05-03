#!/bin/bash

KEY="$HOME/.ssh/simplyblock-ohio.pem"

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --memory <value>                     Set SPDK huge memory allocation(optional)"
    echo "  --cpu-mask <value>                   Set SPDK app CPU mask(optional)"
    echo "  --iobuf_small_pool_count <value>     Set bdev_set_options param(optional)"
    echo "  --iobuf_large_pool_count <value>     Set bdev_set_options param(optional)"
    echo "  --log-del-interval <value>           Set log deletion interval(optional)"
    echo "  --metrics-retention-period <value>   Set metrics retention interval(optional)"
    echo "  --help                               Print this help message"
    exit 0
}

MEMORY=""
CPU_MASK=""
IOBUF_SMALL_POOL_COUNT=""
IOBUF_LARGE_POOL_COUNT=""
LOG_DEL_INTERVAL=""
METRICS_RETENTION_PERIOD=""

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
        --log-del-interval)
            LOG_DEL_INTERVAL="$2"
            shift
            ;;
        --metrics-retention-period)
            METRICS_RETENTION_PERIOD="$2"
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

DESIRED_SIZE_BYTES=2147483648  # 2 GB in bytes
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

command="sbcli-dev cluster create"
if [[ -n "$LOG_DEL_INTERVAL" ]]; then
    command+=" --log-del-interval $LOG_DEL_INTERVAL"
fi
if [[ -n "$METRICS_RETENTION_PERIOD" ]]; then
    command+=" --metrics-retention-period $METRICS_RETENTION_PERIOD"
fi
# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
$command
"

echo ""
echo "Adding other management nodes if they exist.."
echo ""

for ((i = 2; i <= ${#mnodes[@]}; i++)); do
    echo ""
    echo "Adding mgmt node ${i}.."
    echo ""

    ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[${i}]} "
    MANGEMENT_NODE_IP=${mnodes[0]}
    CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
    echo \"Cluster ID is: \${CLUSTER_ID}\"
    sbcli-dev mgmt add \${MANGEMENT_NODE_IP} \${CLUSTER_ID} eth0
    "
done

storage_public_ip=$(echo ${storage_public_ips} | cut -d' ' -f1)

DEVICE_ID=$(ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@${storage_public_ip} "
device_name=\$(lsblk -b -o NAME,SIZE | grep -w "$DESIRED_SIZE_BYTES" | awk '{print \$1}')
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
command="sbcli-dev storage-node add-node"

if [[ -n "$DEVICE_ID" ]]; then
    command+=" --jm-pcie $DEVICE_ID"
fi
if [[ -n "$MEMORY" ]]; then
    command+=" --memory $MEMORY"
fi
if [[ -n "$CPU_MASK" ]]; then
    command+=" --cpu-mask $CPU_MASK"
fi
if [[ -n "$IOBUF_SMALL_POOL_COUNT" ]]; then
    command+=" --iobuf_small_pool_count $IOBUF_SMALL_POOL_COUNT"
fi
if [[ -n "$IOBUF_LARGE_POOL_COUNT" ]]; then
    command+=" --iobuf_large_pool_count $IOBUF_LARGE_POOL_COUNT"
fi

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \"Cluster ID is: \${CLUSTER_ID}\"
sbcli-dev cluster unsuspend \${CLUSTER_ID}

for node in ${storage_private_ips}; do
    echo ""
    echo "joining node \${node}"

    $command \$CLUSTER_ID \${node}:5000 eth0
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
sbcli-dev cluster get-secret \${CLUSTER_ID}
")

echo ""
echo "adding pool testing1"
echo ""

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
sbcli-dev pool add testing1
"

echo "::set-output name=cluster_id::$CLUSTER_ID"
echo "::set-output name=cluster_secret::$CLUSTER_SECRET"
echo "::set-output name=cluster_ip::${mnodes[0]}"

echo ""
echo "Successfully deployed the cluster"
echo ""
