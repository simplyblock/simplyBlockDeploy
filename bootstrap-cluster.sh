#!/bin/zsh

KEY=$HOME/.ssh/simplyblock-ohio.pem
mnodes=($(terraform output -raw mgmt_public_ips))
storage_private_ips=$(terraform output -raw storage_private_ips)

echo "bootstrapping cluster..."

# check if the cloud is successful

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[1]} "
sudo cloud-init status
"
echo ""
echo "Deploying management node..."
echo ""

# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[1]} "
sbcli cluster create
"

echo ""
echo "Adding other management nodes if they exist.."
echo ""

for ((i=2; i <= $#mnodes; i++)); do
    echo ""
    echo "Adding mgmt node ${i}.."
    echo ""

    ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[${i}] "
    MANGEMENT_NODE_IP=${mnodes[1]}
    CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
    echo \"Cluster ID is: \${CLUSTER_ID}\"
    sbcli mgmt add \${MANGEMENT_NODE_IP} \${CLUSTER_ID} eth0
    "
done

echo ""
echo "Adding storage nodes..."
echo ""

# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[1] "
MANGEMENT_NODE_IP=${mnodes[1]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \"Cluster ID is: \${CLUSTER_ID}\"
sbcli cluster unsuspend \${CLUSTER_ID}

for node in ${storage_private_ips}; do
    echo ""
    echo "joining node \${node}"
    sbcli storage-node add-node --cpu-mask 0x3 --memory 16g --bdev_io_pool_size 1000 --bdev_io_cache_size 1000 --iobuf_small_cache_size 10000 --iobuf_large_cache_size 25000  \$CLUSTER_ID \${node}:5000 eth0
    sleep 5
done
"
