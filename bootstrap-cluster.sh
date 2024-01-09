#!/bin/bash

KEY=$HOME/.ssh/simplyblock-ohio.pem
mnodes=(18.218.243.80 3.140.239.130 3.142.120.118)
storage_private_ips="10.0.4.59 10.0.4.67 10.0.4.196 10.0.4.46 10.0.4.246 10.0.4.207 10.0.4.11 10.0.4.13"

echo "bootstrapping cluster..."

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[1] "
sudo cloud-init status
"

# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[1]} "
sbcli cluster create --ha_type ha
"

# node 2
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[2] "
MANGEMENT_NODE_IP=${mnodes[1]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \"Cluster ID is: \${CLUSTER_ID}\"
sbcli mgmt add \${MANGEMENT_NODE_IP} \${CLUSTER_ID} eth0
"

# node 3
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[3] "
MANGEMENT_NODE_IP=${mnodes[1]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \"Cluster ID is: \${CLUSTER_ID}\"
sbcli mgmt add \${MANGEMENT_NODE_IP} \${CLUSTER_ID} eth0
"

# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[1] "
MANGEMENT_NODE_IP=${mnodes[1]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \"Cluster ID is: \${CLUSTER_ID}\"
sbcli cluster unsuspend \${CLUSTER_ID}

for node in ${storage_private_ips}; do
    echo "joining node \${node}"
    sbcli storage-node add-node --cpu-mask 0x3 --memory 16g --bdev_io_pool_size 1000 --bdev_io_cache_size 1000 --iobuf_small_cache_size 10000 --iobuf_large_cache_size 25000  \$CLUSTER_ID \${node}:5000 eth0
    echo ""
    sleep 5
done
"
