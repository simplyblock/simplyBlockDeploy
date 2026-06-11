# Shared component definitions for update-upstreams.sh and publish-upstreams.sh.
# Each entry: "prefix  remote  upstream-branch"
# Source this file; do not execute it directly.

COMPONENTS=(
    "sbcli         sbcli         main"
    "operator      operator      main"
    "helm-charts   helm-charts   main"
    "csi           csi           master"
    "documentation documentation main"
)
