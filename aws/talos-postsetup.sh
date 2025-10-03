#!/usr/bin/env bash

set -euo pipefail

export TALOSCONFIG=$(terraform output -raw talos_config_path)
TALOS_IP=$(terraform output -raw talos_ip)
talosctl config endpoints $TALOS_IP
talosctl config nodes $TALOS_IP
talosctl bootstrap
talosctl health

talosctl kubeconfig .
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
