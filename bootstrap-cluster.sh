#!/bin/bash
set -euo pipefail

KEY="$HOME/.ssh/simplyblock-us-east-2.pem"
TEMP_KEY="/tmp/tmpkey.pem"
nr_hugepages=$NR_HUGEPAGES
BASTION_IP=$BASTION_IP
GRAFANA_ENDPOINT=$GRAFANA_ENDPOINT
mnodes=$MNODES
echo "mgmt_private_ips: ${mnodes}"
IFS=' ' read -ra mnodes <<<"$mnodes"
storage_private_ips=$STORAGE_PRIVATE_IPS


print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --max-lvol  <value>                  Set Maximum lvols (optional)"
    echo "  --max-snap  <value>                  Set Maximum snapshots (optional)"
    echo "  --max-size  <value>                  Set Maximum amount of GB to be utilized on storage node (optional)"
    echo "  --number-of-devices <value>          Set number of devices (optional)"
    echo "  --journal-partition <value>          Set 1: auto-create small partitions for journal on nvme devices. 0: use a separate (the smallest) nvme device of the node for journal (optional)"
    echo "  --iobuf_small_bufsize <value>        Set bdev_set_options param (optional)"
    echo "  --iobuf_large_bufsize <value>        Set bdev_set_options param (optional)"
    echo "  --log-del-interval <value>           Set log deletion interval (optional)"
    echo "  --metrics-retention-period <value>   Set metrics retention interval (optional)"
    echo "  --sbcli-cmd <value>                  Set sbcli command name (optional, default: sbcli-dev)"
    echo "  --spdk-image <value>                 Set SPDK image (optional)"
    echo "  --cpu-mask <value>                   Set SPDK app CPU mask (optional)"
    echo "  --contact-point <value>              Set slack or email contact point for alerting (optional)"
    echo "  --data-chunks-per-stripe <value>     Set Erasure coding schema parameter k (distributed raid) (optional)"
    echo "  --parity-chunks-per-stripe <value>   Set Erasure coding schema parameter n (distributed raid) (optional)"
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
    echo "  --data-nics                          Set Storage network interface name(s). Can be more than one. (optional)"
    echo "  --vcpu-count                         Set Number of vCPUs used for SPDK. (optional)"
    echo "  --id-device-by-nqn                   Use device nqn to identify it instead of serial number. (optional)"
    echo "  --help                               Print this help message"
    exit 0
}

cleanup() {
echo "Cleaning up temp key..."
rm -f "$TEMP_KEY"
}

parse_args() {
# initialize all vars
MAX_LVOL=""
MAX_SNAPSHOT=""
MAX_SIZE=""
NO_DEVICE=""
NUM_PARTITIONS=""
IOBUF_SMALL_BUFFSIZE=""
IOBUF_LARGE_BUFFSIZE=""
LOG_DEL_INTERVAL=""
METRICS_RETENTION_PERIOD=""
SBCLI_CMD="${SBCLI_CMD:-sbcli-dev}"
SBCLI_INSTALL_SOURCE="${SBCLI_BRANCH:+git+https://github.com/simplyblock-io/sbcli.git@${SBCLI_BRANCH}}"
SBCLI_INSTALL_SOURCE="${SBCLI_INSTALL_SOURCE:-${SBCLI_CMD}}"
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
DATANICS=""
VCPU_COUNT=""
ID_DEVICE_BY_NQN=""
K8S_SNODE="false"
HA_JM_COUNT=""
NODES_PER_SOCKET=""
SOCKETS_TO_USE=""
PCI_ALLOWED=""
PCI_BLOCKED=""
NAMESPACE=""

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
    --max-size)
        MAX_SIZE="$2"
        shift
        ;;
    --number-of-devices)
        NO_DEVICE="$2"
        shift
        ;;
    --journal-partition)
        NUM_PARTITIONS="$2"
        shift
        ;;
    --iobuf_small_bufsize)
        IOBUF_SMALL_BUFFSIZE="$2"
        shift
        ;;
     --iobuf_large_bufsize)
        IOBUF_LARGE_BUFFSIZE="$2"
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
    --data-chunks-per-stripe)
        NDCS="$2"
        shift
        ;;
    --parity-chunks-per-stripe)
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
    --data-nics)
        DATANICS="$2"
        shift
        ;;
    --vcpu-count)
        VCPU_COUNT="$2"
        shift
        ;;
    --id-device-by-nqn)
        ID_DEVICE_BY_NQN="$2"
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
}

ssh_exec() {
    local node_ip="$1"
    local cmd="$2"
    ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
    root@${node_ip} "$cmd"
}

install_sbcli_on_node() {
    local node_ip="$1"
    echo "Installing sbcli on node: $node_ip"
    ssh_exec "$node_ip" "
        old_pkg=\$(pip list | grep -i sbcli | awk '{print \$1}')
        if [[ -n \"\${old_pkg}\" ]]; then
            \$old_pkg sn deploy-cleaner
            pip uninstall -y \$old_pkg
        fi
        sudo sysctl -w vm.nr_hugepages=${NR_HUGEPAGES}
        pip install ${SBCLI_INSTALL_SOURCE} --upgrade
    "

    # sbcli configure
    if [[ -n "$2" ]]; then
        local configure_cmd="$2"
        ssh_exec "$node_ip" "
            echo ${configure_cmd} > /root/sn_deploy.log 2>&1
            $configure_cmd >> /root/sn_deploy.log 2>&1 &
            ${SBCLI_CMD} sn deploy --ifname eth0 >> /root/sn_deploy.log 2>&1 &
        "
    fi
}

bootstrap_cluster() {
    local mgmt_ip="$1"
    local command="${SBCLI_CMD} sn deploy-cleaner ; ${SBCLI_CMD} --dev -d cluster create"
    # append optional flags
    [[ -n "$LOG_DEL_INTERVAL" ]] && command+=" --log-del-interval $LOG_DEL_INTERVAL"
    [[ -n "$METRICS_RETENTION_PERIOD" ]] && command+=" --metrics-retention-period $METRICS_RETENTION_PERIOD"
    [[ -n "$CONTACT_POINT" ]] && command+=" --contact-point $CONTACT_POINT"
    [[ -n "$GRAFANA_ENDPOINT" ]] && command+=" --grafana-endpoint $GRAFANA_ENDPOINT"
    [[ -n "$NDCS" ]] && command+=" --data-chunks-per-stripe $NDCS"
    [[ -n "$NPCS" ]] && command+=" --parity-chunks-per-stripe $NPCS"
    [[ -n "$CHUNK_BS" ]] && command+=" --distr-chunk-bs $CHUNK_BS"
    [[ -n "$CAP_WARN" ]] && command+=" --cap-warn $CAP_WARN"
    [[ -n "$CAP_CRIT" ]] && command+=" --cap-crit $CAP_CRIT"
    [[ -n "$PROV_CAP_WARN" ]] && command+=" --prov-cap-warn $PROV_CAP_WARN"
    [[ -n "$PROV_CAP_CRIT" ]] && command+=" --prov-cap-crit $PROV_CAP_CRIT"
    [[ -n "$HA_TYPE" ]] && command+=" --ha-type $HA_TYPE"
    [[ -n "$ENABLE_NODE_AFFINITY" ]] && command+=" --enable-node-affinity"
    [[ -n "$QPAIR_COUNT" ]] && command+=" --qpair-count $QPAIR_COUNT"

    ssh_exec "$mgmt_ip" "$command --ifname eth0"
}

get_cluster_id() {
    ssh_exec "${mnodes[0]}" "${SBCLI_CMD} cluster list | grep simplyblock | awk '{print \$2}'"
}

get_cluster_secret() {
    ssh_exec "${mnodes[0]}" "${SBCLI_CMD} cluster get-secret ${CLUSTER_ID}"
}

add_other_mgmt_nodes() {
    for ((i = 1; i < ${#mnodes[@]}; i++)); do
        ssh_exec "${mnodes[$i]}" "${SBCLI_CMD} mgmt add ${mnodes[0]} ${CLUSTER_ID} ${CLUSTER_SECRET} eth0"
    done
}

add_storage_nodes() {
    if [[ "$K8S_SNODE" == "true" ]]; then
        echo "Skipping storage node addition for k8s nodes"
        return
    fi
    local add_cmd="${SBCLI_CMD} --dev -d storage-node add-node"
    [[ -n "$NUM_PARTITIONS" ]] && add_cmd+=" --journal-partition $NUM_PARTITIONS" #
    [[ -n "$DATANICS" ]] && add_cmd+=" --data-nics $DATANICS" #
    [[ -n "$HA_JM_COUNT" ]] && add_cmd+=" --ha-jm-count $HA_JM_COUNT" #
    [[ -n "$NAMESPACE" ]] && add_cmd+=" --namespace $NAMESPACE" #

    scp -i "$KEY" -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -i $KEY -W %h:%p root@${BASTION_IP}" \
        "$KEY" root@${mnodes[0]}:/tmp/tmpkey.pem

    ssh_exec "${mnodes[0]}" "
        chmod 400 $TEMP_KEY
        for node in ${storage_private_ips}; do
            PCIE=\$(ssh -i $TEMP_KEY -o StrictHostKeyChecking=no root@\$node \"lspci -D | grep -i 'NVM' | awk '{print \\\$1}' | paste -sd ' ' -\")
            full_cmd=\"$add_cmd ${CLUSTER_ID} \$node:5000 eth0 --data-nics eth1 --ssd-pcie \$PCIE\"
            \$full_cmd
            sleep 3
        done
        for node in ${SEC_STORAGE_PRIVATE_IPS:-}; do
            full_cmd=\"$add_cmd --is-secondary-node ${CLUSTER_ID} \$node:5000 eth0 --data-nics eth1\"
            \$full_cmd
            sleep 3
        done
        ${SBCLI_CMD} -d cluster activate ${CLUSTER_ID}"
}

add_pool() {
    ssh_exec "${mnodes[0]}" "${SBCLI_CMD} pool add testing1 ${CLUSTER_ID}"
}

main() {
    parse_args "$@"
    IFS=' ' read -ra mnodes <<< "$MNODES"

    local configure_cmd="${SBCLI_CMD} --dev -d storage-node configure"
    [[ -n "$MAX_LVOL" ]] && configure_cmd+=" --max-lvol $MAX_LVOL"
    [[ -n "$MAX_SIZE" ]] && configure_cmd+=" --max-size $MAX_SIZE"
    [[ -n "$NODES_PER_SOCKET" ]] && configure_cmd+=" --nodes-per-socket $NODES_PER_SOCKET"
    [[ -n "$SOCKETS_TO_USE" ]] && configure_cmd+=" --sockets-to-use $SOCKETS_TO_USE"
    [[ -n "$PCI_ALLOWED" ]] && configure_cmd+=" --pci-allowed $PCI_ALLOWED"
    [[ -n "$PCI_BLOCKED" ]] && configure_cmd+=" --pci-blocked $PCI_BLOCKED"

    for node_ip in ${storage_private_ips}; do install_sbcli_on_node "$node_ip" "$configure_cmd" & done
    for node_ip in ${SEC_STORAGE_PRIVATE_IPS:-}; do install_sbcli_on_node "$node_ip" "$configure_cmd" & done
    for node_ip in ${mnodes[@]}; do install_sbcli_on_node "$node_ip" ""; done

    bootstrap_cluster "${mnodes[0]}"

    CLUSTER_ID=$(get_cluster_id)
    CLUSTER_SECRET=$(get_cluster_secret)

    add_other_mgmt_nodes
    add_storage_nodes
    add_pool

    echo "::set-output name=cluster_id::$CLUSTER_ID"
    echo "::set-output name=cluster_secret::$CLUSTER_SECRET"
    echo "::set-output name=cluster_ip::http://${mnodes[0]}"
    echo "Successfully deployed the cluster"
}

main "$@"
