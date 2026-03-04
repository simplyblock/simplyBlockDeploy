#!/bin/bash
set -euo pipefail

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

BASTION_IP="${BASTION_IP:?BASTION_IP is required}"
mnodes="${K3S_MNODES:?K3S_MNODES is required (space-separated IPs)}"
storage_private_ips="${STORAGE_PRIVATE_IPS:-}"

IFS=' ' read -ra mnodes <<<"$mnodes"
IFS=' ' read -ra storage_nodes <<<"${storage_private_ips}"

echo "mgmt nodes: ${mnodes[*]}"

echo "KEY=$KEY" >> ${GITHUB_OUTPUT:-/dev/stdout}
echo "extra_node_ip=${mnodes[0]}" >> ${GITHUB_OUTPUT:-/dev/stdout}

# Kubernetes version to install (override by exporting K8S_VERSION)
# Example: export K8S_VERSION="1.30.6"
K8S_VERSION="${K8S_VERSION:-1.30.6}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
SVC_CIDR="${SVC_CIDR:-10.96.0.0/12}"

ssh_proxy_cmd() {
  local target_ip="$1"
  cat <<EOF
ssh -i "$KEY" -o StrictHostKeyChecking=no \
  -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \\"$KEY\\" -W %h:%p root@${BASTION_IP}" \
  root@${target_ip}
EOF
}

ssh_run() {
  local ip="$1"
  shift
  ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
    "root@${ip}" "$@"
}

# remote_exec() {
#   local ip="$1"
#   local script="$2"
#   echo "==> SSH into $ip"
#   #$(ssh_proxy_cmd "$ip") "$script"
#   ssh_run "$ip" "bash -lc '$script'"
# }

remote_exec() {
  local ip="$1"
  local script="$2"
  echo "==> SSH into $ip"
  ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p root@${BASTION_IP}" \
    "root@${ip}" bash -s <<REMOTE_EOF
set -euo pipefail
${script}
REMOTE_EOF
}

cleanup_node() {
  local ip="$1"
  remote_exec "$ip" "
    set -e
    echo '[INFO] Cleanup on node...'

    # Uninstall k3s if present
    if command -v k3s >/dev/null 2>&1; then
      echo '[INFO] Uninstalling k3s...'
      /usr/local/bin/k3s-uninstall.sh || true
      /usr/local/bin/k3s-agent-uninstall.sh || true
    fi

    # Reset kubeadm if present
    if command -v kubeadm >/dev/null 2>&1; then
      echo '[INFO] kubeadm reset...'
      kubeadm reset -f || true
    fi

    # Stop kubelet/containerd if present
    systemctl stop kubelet || true
    systemctl stop containerd || true

    # Remove CNI state (optional but helps)
    rm -rf /etc/cni/net.d || true
    rm -rf /var/lib/cni || true

    # Remove old kube config
    rm -rf /etc/kubernetes || true
    rm -rf /var/lib/kubelet/* || true
    rm -rf ~/.kube || true
  "
}

echo "cleaning up old K8s cluster..."
for node_ip in "${mnodes[@]}"; do
  cleanup_node "$node_ip"
done

for node_ip in "${storage_nodes[@]}"; do
  [[ -n "$node_ip" ]] && cleanup_node "$node_ip"
done

install_k8s_node_prereqs() {
  local ip="$1"
  remote_exec "$ip" "
    set -euo pipefail

    echo '[INFO] Installing prereqs...'
    yum install -y fio nvme-cli bc curl ca-certificates iproute-tc conntrack-tools socat ebtables ethtool

    # Kernel modules needed by many CNIs / kube-proxy
    modprobe br_netfilter || true
    modprobe overlay || true
    modprobe nvme-tcp || true
    modprobe nbd || true
    modprobe ipip || true

    cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
nvme-tcp
nbd
EOF

    # Sysctls
    cat >/etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sysctl --system

    # Optional: disable IPv6 (keep your behavior)
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 || true

    swapoff -a

    # Hugepages (keep your behavior; set to 0 by default here)
    total_memory_kb=\$(grep MemTotal /proc/meminfo | awk '{print \$2}')
    total_memory_mb=\$((total_memory_kb / 1024))
    hugepages=0
    sysctl -w vm.nr_hugepages=\$hugepages || true
    echo \"vm.nr_hugepages=\$hugepages\" >/etc/sysctl.d/hugepages.conf
    sysctl --system

    # Disable nm-cloud-setup if it exists
    systemctl disable nm-cloud-setup.service nm-cloud-setup.timer 2>/dev/null || true

    echo '[INFO] Installing containerd (Docker repo)...'

    yum install -y yum-utils device-mapper-persistent-data lvm2

    # Add Docker repo
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install containerd
    yum install -y containerd.io

    mkdir -p /etc/containerd
    containerd config default >/etc/containerd/config.toml

    # IMPORTANT: systemd cgroup driver
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    systemctl enable --now containerd

    echo '[INFO] Setting up Kubernetes repo...'
    cat >/etc/yum.repos.d/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
EOF

    echo '[INFO] Installing kubelet/kubeadm/kubectl...'
    yum install -y kubelet-${K8S_VERSION} kubeadm-${K8S_VERSION} kubectl-${K8S_VERSION} || yum install -y kubelet kubeadm kubectl

    systemctl enable --now kubelet

    echo '[INFO] Done prereqs.'
  "
}

echo "installing kubeadm/kubelet on mgmt nodes..."
for node_ip in "${mnodes[@]}"; do
  install_k8s_node_prereqs "$node_ip"
done

if [[ "$K8S_SNODE" == "true" ]]; then
  echo "installing kubeadm/kubelet on storage nodes..."
  for node_ip in "${storage_nodes[@]}"; do
    [[ -n "$node_ip" ]] && install_k8s_node_prereqs "$node_ip"
  done
fi

# ---- Bootstrap control-plane on mnodes[0] ----
CONTROL_PLANE_IP="${mnodes[0]}"

echo "bootstrapping kubeadm cluster on ${CONTROL_PLANE_IP}..."

remote_exec "$CONTROL_PLANE_IP" "
  set -euo pipefail

  echo '[INFO] kubeadm init...'
  kubeadm init \
    --apiserver-advertise-address=${CONTROL_PLANE_IP} \
    --pod-network-cidr=${POD_CIDR} \
    --service-cidr=${SVC_CIDR}

  mkdir -p \$HOME/.kube
  cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
  chown \$(id -u):\$(id -g) \$HOME/.kube/config

  echo '[INFO] Installing CNI (Calico)...'
  # Calico
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/calico.yaml

  # Allow scheduling on control-plane if you want single-node cluster behavior:
  # (your old script removed the master taint; kubeadm uses control-plane taint)
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

  echo '[INFO] Cluster up.'
"

# ---- Join other nodes ----
JOIN_CMD=$(remote_exec "$CONTROL_PLANE_IP" "kubeadm token create --print-join-command" | tail -n 1)
if [[ -z "$JOIN_CMD" ]]; then
  echo "[ERROR] Could not get kubeadm join command"
  exit 1
fi
echo "Join command: $JOIN_CMD"

for ((i=1; i<${#mnodes[@]}; i++)); do
  node_ip="${mnodes[$i]}"
  remote_exec "$node_ip" "
    set -euo pipefail
    echo '[INFO] Joining as worker...'
    ${JOIN_CMD}
  "
done

if [[ "$K8S_SNODE" == "true" ]]; then
  for node_ip in "${storage_nodes[@]}"; do
    [[ -n "$node_ip" ]] || continue
    echo "Adding primary storage node ${node_ip}.."
    remote_exec "$node_ip" "
      set -euo pipefail
      echo '[INFO] Joining as worker...'
      ${JOIN_CMD}
    "
  done
fi

label_by_ip() {
  local ip="$1"
  local labels="$2"
  remote_exec "$CONTROL_PLANE_IP" "
    set -euo pipefail
    NODE_NAME=\$(kubectl get nodes -o wide | awk '\$6==\"$ip\" {print \$1}')
    if [ -z \"\$NODE_NAME\" ]; then
      echo \"[WARN] Could not find node name for IP $ip\"
      exit 0
    fi
    kubectl label nodes \"\$NODE_NAME\" ${labels} --overwrite
  "
}

label_by_ip "${mnodes[0]}" "type=simplyblock-cache topology.kubernetes.io/region=default"
for ((i=1; i<${#mnodes[@]}; i++)); do
  label_by_ip "${mnodes[$i]}" "type=simplyblock-cache topology.kubernetes.io/region=default"
done

if [[ "$K8S_SNODE" == "true" ]]; then
  for ip in "${storage_nodes[@]}"; do
    [[ -n "$ip" ]] && label_by_ip "$ip" "io.simplyblock.node-type=simplyblock-storage-plane topology.kubernetes.io/region=default"
  done
fi

echo "[INFO] Done."