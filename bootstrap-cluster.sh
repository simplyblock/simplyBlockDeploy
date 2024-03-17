#!/bin/zsh

KEY=$HOME/.ssh/simplyblock-ohio.pem
mnodes=($(terraform output -raw mgmt_public_ips))
storage_private_ips=$(terraform output -raw storage_private_ips)

echo "bootstrapping cluster..."

while true; do
    dstatus=$(ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@${mnodes[1]} "sudo cloud-init status" 2>/dev/null)
    echo "Current status: $dstatus"

    if [[ "$dstatus" == "status: done" ]]; then
        echo "Cloud-init is done. Exiting loop."
        break
    fi

    echo "Waiting for cloud-init to finish..."
    sleep 10
done

echo ""
echo "Deploying management node..."
echo ""

# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[1]} "
sbcli-dev cluster create
"

echo ""
echo "Adding other management nodes if they exist.."
echo ""

for ((i = 2; i <= $#mnodes; i++)); do
    echo ""
    echo "Adding mgmt node ${i}.."
    echo ""

    ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$mnodes[${i}] "
    MANGEMENT_NODE_IP=${mnodes[1]}
    CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
    echo \"Cluster ID is: \${CLUSTER_ID}\"
    sbcli-dev mgmt add \${MANGEMENT_NODE_IP} \${CLUSTER_ID} eth0
    "
done

echo ""
sleep 60
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
    sbcli-dev storage-node add-node --cpu-mask 0x3 --memory 8g --bdev_io_pool_size 1000 --bdev_io_cache_size 1000 --iobuf_small_cache_size 10000 --iobuf_large_cache_size 25000  \$CLUSTER_ID \${node}:5000 eth0
    sleep 5
done
"

echo ""
echo "getting cluster secret"
echo ""

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[1]} "
MANGEMENT_NODE_IP=${mnodes[1]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
sbcli-dev cluster get-secret \${CLUSTER_ID}
"

## deploy monitoring components
storage_private_ips=($(terraform output -raw monitoring_node_public_ips))

echo ""
echo "copying monitoring folder"
echo ""
# copy the monitoring folder into the server
scp -i $KEY -r ./monitoring ec2-user@${storage_private_ips[1]}:/home/ec2-user/.

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${storage_private_ips[1]} "
MANGEMENT_NODE_IP=${mnodes[1]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
sudo yum install -y yum-utils device-mapper-persistent-data lvm2
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum update
sudo yum -y install docker-ce containerd.io --allowerasing
sudo systemctl enable --now docker
systemctl is-active docker
sudo curl -L https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

cd /home/ec2-user/monitoring
sudo docker-compose up -d
./apply_dashboard.sh
"
