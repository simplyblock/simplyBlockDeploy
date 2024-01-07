#!/bin/bash

KEY=$HOME/.ssh/simplyblock-ohio.pem
MGMT_NODES="13.58.234.21 18.118.115.185 3.138.244.0"
storage_private_ips="10.0.4.36 10.0.4.135 10.0.4.82 10.0.4.138 10.0.4.253"

echo "bootstrapping cluster"
mnodes=( $MGMT_NODES )

# node 1
sbcli cluster create --ha_type ha

# node 2
MANGEMENT_NODE_IP=13.58.234.21
CLUSTER_ID=$(curl -X GET "http://${MANGEMENT_NODE_IP}/cluster/" | jq -r '.results[].uuid')
echo "Cluster ID is: ${CLUSTER_ID}"
sbcli mgmt add ${MANGEMENT_NODE_IP} ${CLUSTER_ID} eth0

# node 3
MANGEMENT_NODE_IP=13.58.234.21
CLUSTER_ID=$(curl -X GET "http://${MANGEMENT_NODE_IP}/cluster/" | jq -r '.results[].uuid')
echo "Cluster ID is: ${CLUSTER_ID}"
sbcli mgmt add ${MANGEMENT_NODE_IP} ${CLUSTER_ID} eth0

# node 1
MANGEMENT_NODE_IP=13.58.234.21
CLUSTER_ID=$(curl -X GET "http://${MANGEMENT_NODE_IP}/cluster/" | jq -r '.results[].uuid')
echo "Cluster ID is: ${CLUSTER_ID}"
sbcli cluster unsuspend ${CLUSTER_ID}

for node in $storage_private_ips; do
    sbcli storage-node add-node --cpu-mask 0x3 --memory 16g --bdev_io_pool_size 1000 --bdev_io_cache_size 1000 --iobuf_small_cache_size 10000 --iobuf_large_cache_size 25000  $CLUSTER_ID ${node}:5000 eth0
    sleep 5
done
