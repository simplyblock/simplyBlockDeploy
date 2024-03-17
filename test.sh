#!/bin/zsh

KEY=$HOME/.ssh/geoffrey-test.pem
mnodes=($(terraform output -raw mgmt_public_ips))
storage_private_ips=$(terraform output -raw storage_private_ips)


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
## sudo curl -L https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
## sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

cd /home/ec2-user/monitoring
sudo docker-compose up -d
./apply_dashboard.sh
"
