#!/bin/bash

KEY="$HOME/.ssh/simplyblock-ohio.pem"

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --memory <value>                     Set SPDK huge memory allocation (optional)"
    echo "  --partitions <value>                 Set Number of partitions to create per NVMe device (optional)"
    echo "  --iobuf_small_pool_count <value>     Set bdev_set_options param (optional)"
    echo "  --iobuf_large_pool_count <value>     Set bdev_set_options param (optional)"
    echo "  --log-del-interval <value>           Set log deletion interval (optional)"
    echo "  --metrics-retention-period <value>   Set metrics retention interval (optional)"
    echo "  --sbcli-cmd <value>                  Set sbcli command name (optional, default: sbcli-dev)"
    echo "  --spdk-img <value>                   Set spdk image (optional)"
    echo "  --contact-point <value>              Set slack or email contact point for alerting (optional)"
    echo "  --help                               Print this help message"
    exit 0
}

MEMORY=""
NUM_PARTITIONS=""
IOBUF_SMALL_POOL_COUNT=""
IOBUF_LARGE_POOL_COUNT=""
LOG_DEL_INTERVAL=""
METRICS_RETENTION_PERIOD=""
SBCLI_CMD="${SBCLI_CMD:-sbcli-dev}"
SPDK_IMAGE=""
CONTACT_POINT=""

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
    --memory)
        MEMORY="$2"
        shift
        ;;
    --partitions)
        NUM_PARTITIONS="$2"
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
    --sbcli-cmd)
        SBCLI_CMD="$2"
        shift
        ;;
    --spdk-image)
        SPDK_IMAGE="$2"
        shift
        ;;
    --contact-point)
        CONTACT_POINT="$2"
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

mnodes=$(terraform output -raw mgmt_private_ips)
echo "mgmt_private_ips: ${mnodes}"
IFS=' ' read -ra mnodes <<<"$mnodes"
storage_private_ips=$(terraform output -raw storage_private_ips)

echo "bootstrapping cluster..."

while true; do
    dstatus=$(ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
        ec2-user@${mnodes[0]} "sudo cloud-init status" 2>/dev/null)

    echo "Current status: $dstatus"

    if [[ "$dstatus" == "status: done" ]]; then
        echo "Cloud-init is done. Exiting loop."
        break
    elif [[ "$dstatus" == "status: error" ]]; then
        echo "Cloud-init has failed"
        exit 1
    fi

    echo "Waiting for cloud-init to finish..."
    sleep 10
done

echo ""
echo "Deploying management node..."
echo ""

command="${SBCLI_CMD} sn deploy-cleaner ; ${SBCLI_CMD} cluster create"
echo $command
if [[ -n "$LOG_DEL_INTERVAL" ]]; then
    command+=" --log-del-interval $LOG_DEL_INTERVAL"
fi
if [[ -n "$METRICS_RETENTION_PERIOD" ]]; then
    command+=" --metrics-retention-period $METRICS_RETENTION_PERIOD"
fi
if [[ -n "$CONTACT_POINT" ]]; then
    command+=" --contact-point $CONTACT_POINT"
fi
if [[ -n "$GRAFANA_ENDPOINT" ]]; then
    command+=" --grafana-endpoint $GRAFANA_ENDPOINT"
fi

# node 1

ssh -i "$KEY" -o IPQoS=throughput -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
    ec2-user@${mnodes[0]} "
$command
"

echo ""
echo "Adding other management nodes if they exist.."
echo ""

for ((i = 1; i < ${#mnodes[@]}; i++)); do
    echo ""
    echo "Adding mgmt node ${mnodes[${i}]}.."
    echo ""

    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
        ec2-user@${mnodes[${i}]} "
    MANGEMENT_NODE_IP=${mnodes[0]}
    CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
    echo \"Cluster ID is: \${CLUSTER_ID}\"
    ${SBCLI_CMD} mgmt add \${MANGEMENT_NODE_IP} \${CLUSTER_ID} eth0
    "
done

echo ""
sleep 60
echo "Adding storage nodes..."
echo ""
# node 1
command="${SBCLI_CMD} -d storage-node add-node"

if [[ -n "$MEMORY" ]]; then
    command+=" --memory $MEMORY"
fi
if [[ -n "$IOBUF_SMALL_POOL_COUNT" ]]; then
    command+=" --iobuf_small_pool_count $IOBUF_SMALL_POOL_COUNT"
fi
if [[ -n "$NUM_PARTITIONS" ]]; then
    command+=" --partitions $NUM_PARTITIONS"
    command+=" --jm-percent 3"
fi
if [[ -n "$IOBUF_LARGE_POOL_COUNT" ]]; then
    command+=" --iobuf_large_pool_count $IOBUF_LARGE_POOL_COUNT"
fi
if [[ -n "$SPDK_IMAGE" ]]; then
    command+=" --spdk-image $SPDK_IMAGE"
fi

ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
    ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \"Cluster ID is: \${CLUSTER_ID}\"
${SBCLI_CMD} cluster unsuspend \${CLUSTER_ID}

for node in ${storage_private_ips}; do
    echo ""
    echo "joining node \${node}"
    add_node_command=\"${command} \${CLUSTER_ID} \${node}:5000 eth0\"
    echo "add node command: \${add_node_command}"
    \$add_node_command
    sleep 5
done
"

echo ""
echo "getting cluster id"
echo ""

CLUSTER_ID=$(ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
    ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \${CLUSTER_ID}
")

echo ""
echo "getting cluster secret"
echo ""

CLUSTER_SECRET=$(ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
    ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
${SBCLI_CMD} cluster get-secret \${CLUSTER_ID}
")

echo ""
echo "adding pool testing1"
echo ""

ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
    ec2-user@${mnodes[0]} "
${SBCLI_CMD} pool add testing1 ${CLUSTER_ID}
"

API_INVOKE_URL=$(terraform output -raw api_invoke_url)

echo "::set-output name=cluster_id::$CLUSTER_ID"
echo "::set-output name=cluster_secret::$CLUSTER_SECRET"
echo "::set-output name=cluster_ip::http://${mnodes[0]}"
echo "::set-output name=cluster_api_gateway_endpoint::$API_INVOKE_URL"

echo ""
echo "Successfully deployed the cluster"
echo ""
