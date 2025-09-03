#!/bin/bash

KEY="${KEY:-$HOME/.ssh/id_ed25519}"

echo "reading terraform outputs..."
BASTION_IP=$(terraform output -raw bastion_public_ip)
CLUSTER_ENDPOINT=$(terraform output -raw api_invoke_url)
mnodes=$(terraform output -raw mgmt_private_ips)
storage_node_distro=$(terraform output -raw storage_node_distro)
export SBCLI_CMD=$(terraform output -raw sbcli_cmd)

CLUSTER_ID=$(ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
    ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
${SBCLI_CMD} cluster list | grep simplyblock | awk '{print \$2}'
")

CLUSTER_SECRET=$(ssh -i "$KEY" -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i \"$KEY\" -W %h:%p ec2-user@${BASTION_IP}" \
    ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
${SBCLI_CMD} cluster get-secret ${CLUSTER_ID}
")

echo "cluster ID: $CLUSTER_ID"
echo "cluster secret: $CLUSTER_SECRET"

NETWORK_INTERFACE="ens5"
if [ "$storage_node_distro" = "rhel9" -o "$storage_node_distro" = "rhel10" ]; then
    NETWORK_INTERFACE="eth0"
fi

UBUNTU_HOST="false"
if [ "$storage_node_distro" = "ubuntu2204" -o "$storage_node_distro" = "ubuntu2404" ]; then
    UBUNTU_HOST="true"
fi


helm repo add simplyblock-csi https://raw.githubusercontent.com/simplyblock/simplyblock-csi/master/charts/spdk-csi
helm repo update simplyblock-csi

helm install -n simplyblock --create-namespace spdk-csi simplyblock-csi/spdk-csi \
            --set csiConfig.simplybk.uuid=$CLUSTER_ID \
            --set csiConfig.simplybk.ip=$CLUSTER_ENDPOINT \
            --set csiSecret.simplybk.secret=$CLUSTER_SECRET \
            --set logicalVolume.pool_name=testing1 \
            --set image.simplyblock.tag=R25.6-PRE \
            --set image.csi.tag=v0.1.5 \
            --set storagenode.create=true \
            --set storagenode.ubuntuHost=$UBUNTU_HOST \
            --set logicalVolume.numDataChunks=1 \
            --set logicalVolume.numParityChunks=1 \
            --set storagenode.numPartitions=1 \
            --set storagenode.ifname=$NETWORK_INTERFACE \
            --set image.storageNode.tag=v0.1.3 \
            --set autoClusterActivate=true

