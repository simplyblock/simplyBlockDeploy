#!/bin/bash
set -euo pipefail

KEY="$HOME/.ssh/simplyblock-us-east-2.pem"

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
    echo "  --cpu-mask <value>                   Set SPDK app CPU mask (optional)"
    echo "  --contact-point <value>              Set slack or email contact point for alerting (optional)"
    echo "  --distr-ndcs <value>                 Set distributed NDCs (optional)"
    echo "  --distr-npcs <value>                 Set distributed NPCs (optional)"
    echo "  --distr-bs <value>                   Set distribution block size (optional)"
    echo "  --distr-chunk-bs <value>             Set distributed chunk block size (optional)"
    echo "  --number-of-distribs <value>         Set number of distributions (optional)"
    echo "  --cap-warn <value>                   Set Capacity warning level (optional)"
    echo "  --cap-crit <value>                   Set Capacity critical level (optional)"
    echo "  --prov-cap-warn <value>              Set Provision Capacity warning level (optional)"
    echo "  --prov-cap-crit <value>              Set Provision Capacity critical level (optional)"
    echo "  --ha-type <value>                    Set LVol HA type (optional)"
    echo "  --enable-node-affinity               Enable node affinity for storage nodes (optional)"
    echo "  --qpair-count <value>                Set TCP Transport qpair count (optional)"
    echo "  --k8s-snode                          Set Storage node to run on k8s (default: false)"
    echo "  --spdk-debug                         Allow core dumps on storage nodes (optional)"
    echo "  --disable-ha-jm                      Disable HA JM for distrib creation (optional)"
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
SBCLI_CMD="${SBCLI_CMD:-sbcli-hmdi}"
SPDK_IMAGE=""
CPU_MASK=""
CONTACT_POINT=""
SPDK_DEBUG="false"
NDCS=""
NPCS=""
BS=""
CHUNK_BS=""
NUMBER_DISTRIB=""
CAP_WARN=""
CAP_CRIT=""
PROV_CAP_WARN=""
PROV_CAP_CRIT=""
HA_TYPE=""
ENABLE_NODE_AFFINITY=""
QPAIR_COUNT=""
DISABLE_HA_JM="false"
K8S_SNODE="false"
HA_JM_COUNT=""


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
    --cpu-mask)
        CPU_MASK="$2"
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
    --distr-chunk-bs)
        CHUNK_BS="$2"
        shift
        ;;
    --number-of-distribs)
        NUMBER_DISTRIB="$2"
        shift
        ;;
    --cap-warn)
        CAP_WARN="$2"
        shift
        ;;
    --cap-crit)
        CAP_CRIT="$2"
        shift
        ;;
    --prov-cap-warn)
        PROV_CAP_WARN="$2"
        shift
        ;;
    --prov-cap-crit)
        PROV_CAP_CRIT="$2"
        shift
        ;;
    --ha-type)
        HA_TYPE="$2"
        shift
        ;;
    --enable-node-affinity)
        ENABLE_NODE_AFFINITY="true"
        shift
        ;;
    --qpair-count)
        QPAIR_COUNT="$2"
        shift
        ;;
    --ha-jm-count)
        HA_JM_COUNT="$2"
        shift
        ;;
    --k8s-snode)
        K8S_SNODE="true"
        ;;
    --spdk-debug)
        SPDK_DEBUG="true"
        ;;
    --disable-ha-jm)
        DISABLE_HA_JM="true"
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

nr_hugepages=$NR_HUGEPAGES
BASTION_IP=$BASTION_IP
GRAFANA_ENDPOINT=$GRAFANA_ENDPOINT
mnodes=$MNODES
echo "mgmt_private_ips: ${mnodes}"
IFS=' ' read -ra mnodes <<<"$mnodes"
storage_private_ips=$STORAGE_PRIVATE_IPS
sec_storage_private_ips=$SEC_STORAGE_PRIVATE_IPS

echo "cleaning up old cluster..."

for node_ip in ${mnodes[@]}; do
    echo "SSH into $node_ip and executing commands"
    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
        root@${node_ip} "
        old_pkg=\$(pip list | grep -i sbcli | awk '{print \$1}')
        if [[ -n \"\${old_pkg}\" ]]; then
            \$old_pkg sn deploy-cleaner
            pip uninstall -y \$old_pkg
        fi
        pip install ${SBCLI_CMD} --upgrade

        sleep 10 
    "
done

for node_ip in ${storage_private_ips}; do
    echo "SSH into $node_ip and executing commands"
    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
        root@${node_ip} "
        old_pkg=\$(pip list | grep -i sbcli | awk '{print \$1}')
        if [[ -n \"\${old_pkg}\" ]]; then
            \$old_pkg sn deploy-cleaner
            pip uninstall -y \$old_pkg
        fi
        sudo sysctl -w vm.nr_hugepages=${nr_hugepages}
        pip install ${SBCLI_CMD} --upgrade
        if [ "$K8S_SNODE" == "true" ]; then
            :  # Do nothing
        else
            ${SBCLI_CMD} sn deploy --ifname eth0
        fi

        sleep 10 
    "
done

for node_ip in ${sec_storage_private_ips}; do
    echo "SSH into $node_ip and executing commands"
    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
        root@${node_ip} "
        old_pkg=\$(pip list | grep -i sbcli | awk '{print \$1}')
        if [[ -n \"\${old_pkg}\" ]]; then
            \$old_pkg sn deploy-cleaner
            pip uninstall -y \$old_pkg
        fi
        sudo sysctl -w vm.nr_hugepages=${nr_hugepages}
        pip install ${SBCLI_CMD} --upgrade
        if [ "$K8S_SNODE" == "true" ]; then
            :  # Do nothing
        else
            ${SBCLI_CMD} sn deploy --ifname eth0
        fi
 
        sleep 10 
    "
done


echo "bootstrapping cluster..."

echo ""
echo "Deploying management node..."
echo ""

command="sudo docker swarm leave --force ; ${SBCLI_CMD} -d cluster create"
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
    command+=" --data-chunks-per-stripe $NDCS"
fi
if [[ -n "$NPCS" ]]; then
    command+=" --parity-chunks-per-stripe $NPCS"
fi
if [[ -n "$CHUNK_BS" ]]; then
    command+=" --chunk-size-in-bytes $CHUNK_BS"
fi
if [[ -n "$CAP_WARN" ]]; then
    command+=" --cap-warn $CAP_WARN"
fi
if [[ -n "$CAP_CRIT" ]]; then
    command+=" --cap-crit $CAP_CRIT"
fi
if [[ -n "$PROV_CAP_WARN" ]]; then
    command+=" --prov-cap-warn $PROV_CAP_WARN"
fi
if [[ -n "$PROV_CAP_CRIT" ]]; then
    command+=" --prov-cap-crit $PROV_CAP_CRIT"
fi
if [[ -n "$HA_TYPE" ]]; then
    command+=" --ha-type $HA_TYPE"
fi
if [[ -n "$ENABLE_NODE_AFFINITY" ]]; then
    command+=" --enable-node-affinity"
fi
if [[ -n "$QPAIR_COUNT" ]]; then
    command+=" --qpair-count $QPAIR_COUNT"
fi
echo $command

echo ""
echo "Creating new cluster"
echo ""

ssh -i "$KEY" -o IPQoS=throughput -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
    root@${mnodes[0]} "
$command --ifname eth0
"

echo ""
echo "getting cluster id"
echo ""

CLUSTER_ID=$(ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
    root@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
${SBCLI_CMD} cluster list | grep simplyblock | awk '{print \$2}'
")


echo ""
echo "getting cluster secret"
echo ""

CLUSTER_SECRET=$(ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
    root@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
${SBCLI_CMD} cluster get-secret ${CLUSTER_ID}
")


echo ""
echo "Adding other management nodes if they exist.."
echo ""

for ((i = 1; i < ${#mnodes[@]}; i++)); do
    echo ""
    echo "Adding mgmt node ${mnodes[${i}]}.."
    echo ""

    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
        root@${mnodes[${i}]} "
    MANGEMENT_NODE_IP=${mnodes[0]}
    ${SBCLI_CMD} mgmt add \${MANGEMENT_NODE_IP} ${CLUSTER_ID} ${CLUSTER_SECRET} eth0
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
# if [[ -n "$MAX_SNAPSHOT" ]]; then
#     command+=" --max-snap $MAX_SNAPSHOT"
# fi
if [[ -n "$MAX_PROVISION" ]]; then
    command+=" --max-size $MAX_PROVISION"
fi
if [[ -n "$NO_DEVICE" ]]; then
    command+=" --number-of-devices $NO_DEVICE"
fi
# if [[ -n "$IOBUF_SMALL_POOL_COUNT" ]]; then
#     command+=" --iobuf_small_pool_count $IOBUF_SMALL_POOL_COUNT"
# fi
if [[ -n "$NUM_PARTITIONS" ]]; then
    command+=" --journal-partition $NUM_PARTITIONS"
    # command+=" --jm-percent 3"
fi
# if [[ -n "$IOBUF_LARGE_POOL_COUNT" ]]; then
#     command+=" --iobuf_large_pool_count $IOBUF_LARGE_POOL_COUNT"
# fi
# if [[ -n "$SPDK_IMAGE" ]]; then
#     command+=" --spdk-image $SPDK_IMAGE"
# fi
# if [[ -n "$CPU_MASK" ]]; then
#     command+=" --cpu-mask $CPU_MASK"
# fi
# if [ "$DISABLE_HA_JM" == "true" ]; then
#     command+=" --disable-ha-jm"
# fi
# if [ "$SPDK_DEBUG" == "true" ]; then
#     command+=" --spdk-debug"
# fi
# if [[ -n "$NUMBER_DISTRIB" ]]; then
#     command+=" --number-of-distribs $NUMBER_DISTRIB"
# fi
# if [[ -n "$HA_JM_COUNT" ]]; then
#     command+=" --ha-jm-count $HA_JM_COUNT"
# fi


if [ "$K8S_SNODE" == "true" ]; then
    :  # Do nothing

else
    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
        root@${mnodes[0]} "
    MANGEMENT_NODE_IP=${mnodes[0]}
    for node in ${storage_private_ips}; do
        echo ""
        echo "joining node \${node}"
        add_node_command=\"${command} ${CLUSTER_ID} \${node}:5000 eth0 --data-nics eth1\"
        echo "add node command: \${add_node_command}"
        \$add_node_command
        sleep 3
    done

    for node in ${sec_storage_private_ips}; do
        echo ""
        echo "joining secondary node \${node}"
        add_node_command=\"${command} --is-secondary-node ${CLUSTER_ID} \${node}:5000 eth0 --data-nics eth1\"
        echo "add node command: \${add_node_command}"
        \$add_node_command
        sleep 3
    done"

    echo ""
    echo "Running Cluster Activate"
    echo ""
    
    ssh -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
        root@${mnodes[0]} "
    MANGEMENT_NODE_IP=${mnodes[0]}
    ${SBCLI_CMD} -d cluster activate ${CLUSTER_ID}
    "
fi

echo ""
echo "adding pool testing1"
echo ""

ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
    root@${mnodes[0]} "
${SBCLI_CMD} pool add testing1 ${CLUSTER_ID}
"


echo "::set-output name=cluster_id::$CLUSTER_ID"
echo "::set-output name=cluster_secret::$CLUSTER_SECRET"
echo "::set-output name=cluster_ip::http://${mnodes[0]}"

echo ""
echo "Successfully deployed the cluster"
echo ""

