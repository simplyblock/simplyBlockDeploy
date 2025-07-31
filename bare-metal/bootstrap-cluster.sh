#!/bin/bash
set -euo pipefail

KEY="$HOME/.ssh/simplyblock-us-east-2.pem"
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
    echo "  --enable-test-device                 Enable creation of test device (optional)"
    echo "  --full-page-unmap                    Enable use_map_whole_page_on_1st_write flaf in bdev_distrib_create and bdev_alceml_create (optional)"
    echo "  --data-nics                          Set Storage network interface name(s). Can be more than one. (optional)"
    echo "  --vcpu-count                         Set Number of vCPUs used for SPDK. (optional)"
    echo "  --id-device-by-nqn                   Use device nqn to identify it instead of serial number. (optional)"
    echo "  --jm-percent                         Number in percent to use for JM from each device (optional)"
    echo "  --size-of-device                     Size of device per storage node (optional)"
    echo "  --namespace                          The Kubernetes Namespace in which storage node needs to be installed (optional)"
    echo "  --mode                               The Environment to deploy management services (optional)"
    echo "  --cleanup                            cleans up the cluster before deployment"
    echo "  --help                               Print this help message"
    exit 0
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
MODE=""
JM_PERCENT=""
PARTITION_SIZE=""
ENABLE_TEST_DEVICE="false"
FULL_PAGE_UNMAP="false"
CLEAN_UP="false"

PROXY_URL="http://34.1.171.127:5000"
INSECURE_URL="34.1.171.127:5000"

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
    --enable-test-device)
        ENABLE_TEST_DEVICE="true"
        ;;
    --full-page-unmap)
        FULL_PAGE_UNMAP="true"
        ;;
    --cleanup)
        CLEAN_UP="true"
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
    --jm-percent)
        JM_PERCENT="$2"
        shift
        ;;
    --size-of-device)
        PARTITION_SIZE="$2"
        shift
        ;;
    --mode)
        MODE="$2"
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

setup_docker_proxy() {
    DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

    if [ ! -d "/etc/docker" ]; then
        sudo mkdir -p /etc/docker
    fi

    if [ ! -f "$DOCKER_DAEMON_JSON" ]; then
        sudo bash -c "echo '{}' > $DOCKER_DAEMON_JSON"
    fi

    if ! command -v jq &> /dev/null; then
        echo "jq could not be found. Please install jq."
        exit 1
    fi

    CONFIG=$(sudo cat "$DOCKER_DAEMON_JSON")
    PROXY_URL=$1
    INSECURE_URL=$2
    echo "Setting up Docker proxy with URL: $PROXY_URL and Insecure URL: $INSECURE_URL"

    UPDATED_CONFIG=$(echo "$CONFIG" | jq --arg url "$PROXY_URL" '
    .["registry-mirrors"] = (.["registry-mirrors"] // []) + (if (.["registry-mirrors"] // []) | index($url) then [] else [$url] end)
    ')

    UPDATED_CONFIG=$(echo "$UPDATED_CONFIG" | jq --arg url "$INSECURE_URL" '
    .["insecure-registries"] = (.["insecure-registries"] // []) + (if (.["insecure-registries"] // []) | index($url) then [] else [$url] end)
    ')

    echo "$UPDATED_CONFIG" | sudo tee "$DOCKER_DAEMON_JSON.tmp" > /dev/null
    sudo mv "$DOCKER_DAEMON_JSON.tmp" "$DOCKER_DAEMON_JSON"

    echo "Restarting Docker..."
    sudo systemctl restart docker || true
    echo "Done."
}

install_sbcli_on_node() {
    local node_ip="$1"
    ssh_exec "$node_ip" "$(declare -f setup_docker_proxy); setup_docker_proxy $PROXY_URL $INSECURE_URL"

    echo "Installing sbcli on node: $node_ip"
    ssh_exec "$node_ip" "
        old_pkg=\$(pip list | grep -i sbcli | awk '{print \$1}')
        if [[ -n \"\${old_pkg}\" ]]; then
            \$old_pkg sn deploy-cleaner
            pip uninstall -y \$old_pkg
        fi
        sudo sysctl -w vm.nr_hugepages=${NR_HUGEPAGES}
        sudo yum install -y git
        pip install ${SBCLI_INSTALL_SOURCE} --upgrade
    "
    if [ -n "${SIMPLY_BLOCK_DOCKER_IMAGE+x}" ]; then
        ssh_exec "$node_ip" "sed -i \"s#^\(SIMPLY_BLOCK_DOCKER_IMAGE=\).*#\1${SIMPLY_BLOCK_DOCKER_IMAGE}#\" /usr/local/lib/python3.9/site-packages/simplyblock_core/env_var"
    fi
    if [ -n "${SIMPLY_BLOCK_SPDK_ULTRA_IMAGE+x}" ]; then
        ssh_exec "$node_ip" "sed -i \"s#^\(SIMPLY_BLOCK_SPDK_ULTRA_IMAGE=\).*#\1${SIMPLY_BLOCK_SPDK_ULTRA_IMAGE}#\" /usr/local/lib/python3.9/site-packages/simplyblock_core/env_var"
    fi

    # sbcli configure
    if [[ -n "$2" ]]; then
        local configure_cmd="$2"

        # cleanup partitions
        ssh_exec "$node_ip" "
              for disk in nvme0n1 nvme1n1 nvme2n1 nvme3n1; do
                for part in 1 2; do
                  echo \"Cleaning up partitions on \$disk:\$part\"
                  sudo parted /dev/\$disk rm \$part || true
                done
              done
        "

        ssh_exec "$node_ip" "
            echo ${configure_cmd} > /root/sn_deploy.log 2>&1
            $configure_cmd >> /root/sn_deploy.log 2>&1
            if [ \"$K8S_SNODE\" == \"true\" ]; then
                :
            else
                ${SBCLI_CMD} sn deploy --ifname eth0 >> /root/sn_deploy.log 2>&1 &
            fi
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
    [[ -n "$MODE" ]] && command+=" --mode $MODE"
    [[ -n "$MODE" && "$MODE" == "kubernetes" ]] && command+=" --mgmt-ip $mgmt_ip"

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
        local command="${SBCLI_CMD} mgmt add ${mnodes[0]} ${CLUSTER_ID} ${CLUSTER_SECRET}"
        # append optional flags
        [[ -n "$MODE" ]] && command+=" --mode $MODE"
        [[ -z "$MODE" || "$MODE" == "docker" ]] && command+=" --ifname eth0"
        [[ -n "$MODE" && "$MODE" == "kubernetes" ]] && command+=" --mgmt-ip ${mnodes[$i]}"

        if [[ "$MODE" == "kubernetes" ]]; then
            ssh_exec "$mgmt_ip" "$command"
        else
            ssh_exec "${mnodes[$i]}" "$command"
        fi
    done
}

cleanup_and_reboot() {

    for node_ip in ${storage_private_ips}; do
        echo "SSH into $node_ip and run cleanup commands"
            ssh_exec "$node_ip" "

            sudo systemctl stop firewalld
            sudo systemctl stop ufw
            sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1

            ${SBCLI_CMD} sn deploy-cleaner || { echo \"Error: ${SBCLI_CMD} deploy-cleaner failed\";}

            docker stop \$(docker ps -aq) || true
            docker rm -f \$(docker ps -aq) || true
            docker builder prune --all -f
            docker system prune -af
            docker volume prune -f
            docker rmi -f \$(docker images -aq) || true

            # Remove sbcli
            pip uninstall -y ${SBCLI_CMD} || { echo \"Error: Failed to uninstall ${SBCLI_CMD}\";}
            rm -rf /usr/local/bin/sbc*

            /usr/local/bin/k3s-agent-uninstall.sh || { echo \"Error: Failed to uninstall k3s agent\";}
            echo "rebooting the node"
            sudo reboot || { echo "Error: Failed to reboot the node";}
        "
    done

    for ((i = 0; i < ${#mnodes[@]}; i++)); do
        ssh_exec "${mnodes[$i]}" "
            sudo systemctl stop firewalld
            sudo systemctl stop ufw
            sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1

            ${SBCLI_CMD} sn deploy-cleaner || { echo \"Error: ${SBCLI_CMD} deploy-cleaner failed\";}

            docker stop \$(docker ps -aq) || true
            docker rm -f \$(docker ps -aq) || true
            docker builder prune --all -f
            docker system prune -af
            docker volume prune -f
            docker rmi -f \$(docker images -aq) || true

            # Remove ${SBCLI_CMD}
            pip uninstall -y ${SBCLI_CMD} || { echo \"Error: Failed to uninstall ${SBCLI_CMD}\";}
            rm -rf /usr/local/bin/sbc*

            /usr/local/bin/k3s-agent-uninstall.sh || { echo \"Error: Failed to uninstall k3s agent\";}
        "
    done
}

add_storage_nodes() {
    if [[ "$K8S_SNODE" == "true" ]]; then
        echo "Skipping storage node addition for k8s nodes"
        return
    fi
    local add_cmd="${SBCLI_CMD} --dev -d storage-node add-node"
    [[ -n "$MAX_SNAPSHOT" ]] && add_cmd+=" --max-snap $MAX_SNAPSHOT"
    [[ -n "$IOBUF_SMALL_BUFFSIZE" ]] && add_cmd+=" --iobuf_small_bufsize $IOBUF_SMALL_BUFFSIZE"
    [[ -n "$NUM_PARTITIONS" ]] && add_cmd+=" --journal-partition $NUM_PARTITIONS"
    [[ -n "$IOBUF_LARGE_BUFFSIZE" ]] && add_cmd+=" --iobuf_large_bufsize $IOBUF_LARGE_BUFFSIZE"
    [[ -n "$DATANICS" ]] && add_cmd+=" --data-nics $DATANICS"
    [[ -n "$ID_DEVICE_BY_NQN" ]] && add_cmd+=" --id-device-by-nqn $ID_DEVICE_BY_NQN"
    [[ -n "$SPDK_IMAGE" ]] && add_cmd+=" --spdk-image $SPDK_IMAGE"
    [[ "$DISABLE_HA_JM" == "true" ]] && add_cmd+=" --disable-ha-jm"
    [[ "$ENABLE_TEST_DEVICE" == "true" ]] && add_cmd+=" --enable-test-device"
    [[ "$FULL_PAGE_UNMAP" == "true" ]] && add_cmd+=" --full-page-unmap"
    [[ "$SPDK_DEBUG" == "true" ]] && add_cmd+=" --spdk-debug"
    [[ -n "$HA_JM_COUNT" ]] && add_cmd+=" --ha-jm-count $HA_JM_COUNT"
    [[ -n "$JM_PERCENT" ]] && add_cmd+=" --jm-percent $JM_PERCENT"
    [[ -n "$PARTITION_SIZE" ]] && add_cmd+=" --size-of-device $PARTITION_SIZE"

    ssh_exec "${mnodes[0]}" "
        for node in ${storage_private_ips}; do
            full_cmd=\"$add_cmd ${CLUSTER_ID} \$node:5000 eth0\"
            echo \"\$full_cmd\"
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

    # cleanup if requested
    if [[ "$CLEAN_UP" == "true" ]]; then
        echo "Cleaning up the cluster before deployment"
        cleanup_and_reboot
    fi

    local configure_cmd="${SBCLI_CMD} --dev -d storage-node configure"
    [[ -n "$MAX_LVOL" ]] && configure_cmd+=" --max-lvol $MAX_LVOL"
    [[ -n "$MAX_SIZE" ]] && configure_cmd+=" --max-size $MAX_SIZE"
    [[ -n "$NODES_PER_SOCKET" ]] && configure_cmd+=" --nodes-per-socket $NODES_PER_SOCKET"
    [[ -n "$SOCKETS_TO_USE" ]] && configure_cmd+=" --sockets-to-use $SOCKETS_TO_USE"
    [[ -n "$PCI_ALLOWED" ]] && configure_cmd+=" --pci-allowed $PCI_ALLOWED"
    [[ -n "$PCI_BLOCKED" ]] && configure_cmd+=" --pci-blocked $PCI_BLOCKED"

    for node_ip in ${storage_private_ips}; do install_sbcli_on_node "$node_ip" "$configure_cmd" & done
    for node_ip in ${mnodes[@]}; do install_sbcli_on_node "$node_ip" ""; done

    bootstrap_cluster "${mnodes[0]}"

    CLUSTER_ID=$(get_cluster_id)
    CLUSTER_SECRET=$(get_cluster_secret)

    add_other_mgmt_nodes
    add_storage_nodes
    add_pool

    echo "cluster_id=$CLUSTER_ID" >> ${GITHUB_OUTPUT:-/dev/stdout}
    echo "cluster_secret=$CLUSTER_SECRET" >> ${GITHUB_OUTPUT:-/dev/stdout}
    echo "cluster_ip=http://${mnodes[0]}" >> ${GITHUB_OUTPUT:-/dev/stdout}
    echo "Successfully deployed the cluster"
}

main "$@"
