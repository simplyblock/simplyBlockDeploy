#!/bin/bash


# create cluster
# pick a main cluster
sbcli cluster create --ha_type ha

# get the mgmt node IP, clusterID

# node 2
sbcli mgmt add 10.0.4.23 f7cd5a2b-c4df-4036-ba58-e8eda0bb302c eth0

# node 3
sbcli mgmt add 10.0.4.23 f7cd5a2b-c4df-4036-ba58-e8eda0bb302c eth0

# on the mgmt node, unsuspend the cluster
sbcli cluster unsuspend f7cd5a2b-c4df-4036-ba58-e8eda0bb302c

storage_private_ips="10.0.4.142 10.0.4.34 10.0.4.39 10.0.4.86 10.0.4.192 10.0.4.129 10.0.4.4 10.0.4.184"


MANGEMENT_NODE_IP=18.117.84.166
CLUSTER_ID=$(curl -X GET "http://${MANGEMENT_NODE_IP}/cluster/" | jq -r '.results[].uuid')

for node in $storage_private_ips; do
    sbcli storage-node add-node --cpu-mask 0x3 --memory 16g --bdev_io_pool_size 1000 --bdev_io_cache_size 1000 --iobuf_small_cache_size 10000 --iobuf_large_cache_size 25000  $CLUSTER_ID ${node}:5000 eth0
    sleep 5
done
