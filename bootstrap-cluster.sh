#!/bin/bash
set -euo pipefail

KEY="$HOME/.ssh/simplyblock-ohio.pem"

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --max-lvol  <value>                  Set Maximum lvols (optional)"
    echo "  --max-snap  <value>                  Set Maximum snapshots (optional)"
    echo "  --max-prov  <value>                  Set Maximum cluster size (optional)"
    echo "  --number-of-devices <value>          Set number of devices (optional)"
    echo "  --partitions <value>                 Set Number of partitions to create per NVMe device (optional)"
    echo "  --iobuf_small_pool_count <value>     Set bdev_set_options param (optional)"
    echo "  --iobuf_large_pool_count <value>     Set bdev_set_options param (optional)"
    echo "  --log-del-interval <value>           Set log deletion interval (optional)"
    echo "  --metrics-retention-period <value>   Set metrics retention interval (optional)"
    echo "  --sbcli-cmd <value>                  Set sbcli command name (optional, default: sbcli-dev)"
    echo "  --spdk-image <value>                 Set SPDK image (optional)"
    echo "  --contact-point <value>              Set slack or email contact point for alerting (optional)"
    echo "  --distr-ndcs <value>                 Set distributed NDCs (optional)"
    echo "  --distr-npcs <value>                 Set distributed NPCs (optional)"
    echo "  --distr-bs <value>                   Set distribution block size (optional)"
    echo "  --distr-chunk-bs <value>             Set distributed chunk block size (optional)"
    echo "  --number-of-distribs <value>         Set number of distributions (optional)"
    echo "  --spdk-debug                         Allow core dumps on storage nodes (optional)"
    echo "  --help                               Print this help message"
    exit 0
}

MAX_LVOL=""
MAX_SNAPSHOT=""
MAX_PROVISION=""
NO_DEVICE=""
NUM_PARTITIONS=""
IOBUF_SMALL_POOL_COUNT=""
IOBUF_LARGE_POOL_COUNT=""
LOG_DEL_INTERVAL=""
METRICS_RETENTION_PERIOD=""
SBCLI_CMD="${SBCLI_CMD:-sbcli-dev}"
SPDK_IMAGE=""
CONTACT_POINT=""
SPDK_DEBUG="false"
NDCS=""
NPCS=""
BS=""
CHUNK_BS=""
NUMBER_DISTRIB=""


while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
    --max-lvol)
        MAX_LVOL="$2"
        shift
        ;;
    --max-snap)
        MAX_SNAPSHOT="$2"
        shift
        ;;
    --max-prov)
        MAX_PROVISION="$2"
        shift
        ;;
    --number-of-devices)
        NO_DEVICE="$2"
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
    --distr-ndcs)
        NDCS="$2"
        shift
        ;;
    --distr-npcs)
        NPCS="$2"
        shift
        ;;
    --distr-bs)
        BS="$2"
        shift
        ;;
    --distr-chunk-bs)
        CHUNK_BS="$2"
        shift
        ;;
    --number-of-distribs)
        NUMBER_DISTRIB="$2"
        shift
        ;;
    --spdk-debug)
        SPDK_DEBUG="true"
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

command="${SBCLI_CMD} sn deploy-cleaner ; ${SBCLI_CMD} -d cluster create"
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
if [[ -n "$NDCS" ]]; then
    command+=" --distr-ndcs $NDCS"
fi
if [[ -n "$NPCS" ]]; then
    command+=" --distr-npcs $NPCS"
fi
if [[ -n "$BS" ]]; then
    command+=" --distr-bs $BS"
fi
if [[ -n "$CHUNK_BS" ]]; then
    command+=" --distr-chunk-bs $CHUNK_BS"
fi
echo $command

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
sleep 3
echo "Adding storage nodes..."
echo ""
# node 1
command="${SBCLI_CMD} -d storage-node add-node"

if [[ -n "$MAX_LVOL" ]]; then
    command+=" --max-lvol $MAX_LVOL"
fi
if [[ -n "$MAX_SNAPSHOT" ]]; then
    command+=" --max-snap $MAX_SNAPSHOT"
fi
if [[ -n "$MAX_PROVISION" ]]; then
    command+=" --max-prov $MAX_PROVISION"
fi
if [[ -n "$NO_DEVICE" ]]; then
    command+=" --number-of-devices $NO_DEVICE"
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
if [ "$SPDK_DEBUG" == "true" ]; then
    command+=" --spdk-debug"
fi

if [[ -n "$NUMBER_DISTRIB" ]]; then
    command+=" --number-of-distribs $NUMBER_DISTRIB"
fi

if [ "$SBCLI_CMD" = "sbcli-lvol-raid" ]; then
    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
        ec2-user@${mnodes[0]} "
    MANGEMENT_NODE_IP=${mnodes[0]}
    CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
    echo \"Cluster ID is: \${CLUSTER_ID}\"

    for node in ${storage_private_ips}; do
        echo ""
        echo "joining node \${node}"
        add_node_command=\"${command} \${CLUSTER_ID} \${node}:5000 eth0\"
        echo "add node command: \${add_node_command}"
        \$add_node_command
        sleep 3
    done"
else
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
        sleep 3
    done"
fi

if [ "$SBCLI_CMD" = "sbcli-lvol-raid" ]; then
    echo ""
    echo "Running Cluster Activate"
    echo ""

    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
        ec2-user@${mnodes[0]} "
    MANGEMENT_NODE_IP=${mnodes[0]}
    CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
    echo \"Cluster ID is: \${CLUSTER_ID}\"
    ${SBCLI_CMD} cluster activate \${CLUSTER_ID}
    "
fi

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
