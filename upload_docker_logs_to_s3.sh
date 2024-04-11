#!/bin/bash

KEY="$HOME/.ssh/simplyblock-ohio.pem"

SECRET_VALUE=$(terraform output -raw secret_value)
KEY_NAME=$(terraform output -raw key_name)

ssh_dir="$HOME/.ssh"

if [ ! -d "$ssh_dir" ]; then
    mkdir -p "$ssh_dir"
    echo "Directory $ssh_dir created."
else
    echo "Directory $ssh_dir already exists."
fi

if [[ -n "$SECRET_VALUE" ]]; then
    rm "$HOME/.ssh/$KEY_NAME"
    echo "$SECRET_VALUE" > "$HOME/.ssh/$KEY_NAME"
    KEY="$HOME/.ssh/$KEY_NAME"
    chmod 400 "$KEY"
else
    echo "Failed to retrieve secret value. Falling back to default key."
fi

echo "Set your AWS credentials and region"

AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=$AWS_REGION
S3_BUCKET=$S3_BUCKET_NAME

mnodes=$(terraform output -raw mgmt_public_ips)

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
sudo yum install -y unzip
if [ ! -f "awscliv2.zip" ]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
else
    echo "awscli already exists."
fi

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
aws configure set default.region $AWS_DEFAULT_REGION
aws configure set default.output json

current_datetime=\$(date +"%Y-%m-%d_%H-%M-%S")

LOCAL_LOGS_DIR="\$current_datetime/docker-logs"

mkdir -p "\$LOCAL_LOGS_DIR"

DOCKER_CONTAINER_IDS=\$(sudo docker ps -q)

echo "\$DOCKER_CONTAINER_IDS"
for CONTAINER_ID in \$DOCKER_CONTAINER_IDS; do
    CONTAINER_NAME=\$(sudo docker inspect --format="{{.Name}}" "\$CONTAINER_ID" | sed 's/\///')
    
    sudo docker logs "\$CONTAINER_ID" > "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt"
    
    aws s3 cp "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt" "s3://$S3_BUCKET/\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt"
done
rm -rf "\$current_datetime"
"
