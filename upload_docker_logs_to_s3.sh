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
    KEY="$HOME/.ssh/$KEY_NAME"
    if [ -f "$HOME/.ssh/$KEY_NAME" ]; then
        echo "The SSH key: ${KEY} already exists locally"
    else
        echo "$SECRET_VALUE" >"$KEY"
        chmod 400 "$KEY"
    fi
else
    echo "Failed to retrieve secret value. Falling back to default key."
fi

# AWS credentials
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=$AWS_REGION
S3_BUCKET=$S3_BUCKET_NAME

# Check if K8s flag is provided
K8S=false
NAMESPACE="spdk-csi"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --k8s) K8S=true ;;
        --namespace) NAMESPACE="$2"; shift ;;
    esac
    shift
done

# Management node log collection (common to both setups)
mnodes=$(terraform output -raw mgmt_private_ips)
echo "mgmt_private_ips: ${mnodes}"
IFS=' ' read -ra mnodes <<<"$mnodes"
BASTION_IP=$(terraform output -raw bastion_public_ip)

sudo yum install -y unzip

ARCH=$(uname -m)

if [[ $ARCH == "x86_64" ]]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
elif [[ $ARCH == "aarch64" ]]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
    echo "Unsupported architecture: \$ARCH"
    exit 1
fi
unzip -q awscliv2.zip
sudo ./aws/install --update

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
aws configure set default.region $AWS_DEFAULT_REGION
aws configure set default.output json

# Fetch logs for management nodes
ssh -i "$KEY" -o IPQoS=throughput -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i "$KEY" -W %h:%p ec2-user@${BASTION_IP}" \
    ec2-user@${mnodes[0]} "
sudo yum install -y unzip zip
ARCH=\$(uname -m)

sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws awscliv2.zip aws

if [[ \$ARCH == "x86_64" ]]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
elif [[ \$ARCH == "aarch64" ]]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
    echo "Unsupported architecture: \$ARCH"
    exit 1
fi
unzip -q awscliv2.zip
sudo ./aws/install --update

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
aws configure set default.region $AWS_DEFAULT_REGION
aws configure set default.output json

LOCAL_LOGS_DIR="$RUN_ID"

mkdir -p "\$LOCAL_LOGS_DIR"

if [ -d /etc/foundationdb/ ]; then
  sudo zip -q -r \$LOCAL_LOGS_DIR/fdb.zip /etc/foundationdb/
  aws s3 cp \$LOCAL_LOGS_DIR/fdb.zip s3://$S3_BUCKET/\$LOCAL_LOGS_DIR/mgmt/fdb.zip
fi

DOCKER_CONTAINER_IDS=\$(sudo docker ps -aq)

echo "\$DOCKER_CONTAINER_IDS"
for CONTAINER_ID in \$DOCKER_CONTAINER_IDS; do
    CONTAINER_NAME=\$(sudo docker inspect --format="{{.Name}}" "\$CONTAINER_ID" | sed 's/\///')

    sudo docker logs "\$CONTAINER_ID" &> "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt"

    aws s3 cp "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt" "s3://$S3_BUCKET/\$LOCAL_LOGS_DIR/mgmt/\$CONTAINER_NAME.txt"
done
rm -rf "\$LOCAL_LOGS_DIR"
sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws awscliv2.zip aws
"

# For storage nodes, different behavior for K8s and Docker Swarm
if [ "$K8S" = true ]; then

    node_private_ips=$(kubectl get nodes -o=jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
    for node in $node_private_ips; do
        echo "Restarting k3s worker nodes: ${node}"
        ssh -i "$KEY" -o IPQoS=throughput -o StrictHostKeyChecking=no \
            -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
            -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i "$KEY" -W %h:%p ec2-user@${BASTION_IP}" \
            ec2-user@${node} "

            sudo systemctl restart k3s-agent

            sudo yum install -y unzip
            ARCH=\$(uname -m)

            sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws awscliv2.zip aws

            if [[ \$ARCH == "x86_64" ]]; then
                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            elif [[ \$ARCH == "aarch64" ]]; then
                curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
            else
                echo "Unsupported architecture: \$ARCH"
                exit 1
            fi
            unzip -q awscliv2.zip
            sudo ./aws/install --update

            aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
            aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
            aws configure set default.region $AWS_DEFAULT_REGION
            aws configure set default.output json

            LOCAL_LOGS_DIR="$RUN_ID"

            mkdir -p "\$LOCAL_LOGS_DIR"

            # Look for core dump files and upload to S3
            for DUMP_FILE in /etc/simplyblock/*; do
                if [ -f "\$DUMP_FILE" ]; then
                    echo "Uploading dump file: \$DUMP_FILE"
                    aws s3 cp "\$DUMP_FILE" "s3://$S3_BUCKET/\$LOCAL_LOGS_DIR/storage/${node}/$(basename "$DUMP_FILE")" --storage-class STANDARD --only-show-errors
                fi
            done

            rm -rf "\$LOCAL_LOGS_DIR"
            sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws awscliv2.zip aws
            "
    done
    echo "Using Kubernetes to collect logs from pods in namespace: $NAMESPACE"

    # Get all pods in the specified namespace
    PODS=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

    for POD in $PODS; do
        echo "Getting logs from pod: $POD in namespace: $NAMESPACE"

        # Get containers in the pod
        CONTAINERS=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}')

        for CONTAINER in $CONTAINERS; do
            LOG_FILE="${POD}_${CONTAINER}.log"
            echo "Collecting logs for container: $CONTAINER in pod: $POD"

            # Get container logs and save to local
            kubectl logs "$POD" -n "$NAMESPACE" -c "$CONTAINER" > "$LOG_FILE"

            # Upload logs to S3 under github_run_id/pod_name folder
            aws s3 cp "$LOG_FILE" "s3://$S3_BUCKET/$RUN_ID/$POD/$CONTAINER.log"

            # Clean up local logs
            rm -f "$LOG_FILE"
        done
    done

    echo "Kubernetes logs collected and uploaded to S3 under the GitHub run ID folder $RUN_ID."

else
    # Docker Swarm setup for storage nodes (existing behavior)
    echo "Using Docker Swarm to collect logs from storage nodes"
    storage_private_ips=$(terraform output -raw storage_private_ips)

    for node in $storage_private_ips; do
        echo "Getting logs from storage node: ${node}"
        ssh -i "$KEY" -o IPQoS=throughput -o StrictHostKeyChecking=no \
            -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
            -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i "$KEY" -W %h:%p ec2-user@${BASTION_IP}" \
            ec2-user@${node} "

            sudo yum install -y unzip
            ARCH=\$(uname -m)

            sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws awscliv2.zip aws

            if [[ \$ARCH == "x86_64" ]]; then
                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            elif [[ \$ARCH == "aarch64" ]]; then
                curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
            else
                echo "Unsupported architecture: \$ARCH"
                exit 1
            fi

            unzip -q awscliv2.zip
            sudo ./aws/install --update

            aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
            aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
            aws configure set default.region $AWS_DEFAULT_REGION
            aws configure set default.output json


            LOCAL_LOGS_DIR="$RUN_ID"

            mkdir -p "\$LOCAL_LOGS_DIR"

            # Look for core dump files and upload to S3
            for DUMP_FILE in /etc/simplyblock/*; do
                if [ -f "\$DUMP_FILE" ]; then
                    echo "Uploading dump file: \$DUMP_FILE"
                    aws s3 cp "\$DUMP_FILE" "s3://$S3_BUCKET/\$LOCAL_LOGS_DIR/storage/${node}/$(basename "$DUMP_FILE")" --storage-class STANDARD --only-show-errors
                fi
            done

            DOCKER_CONTAINER_IDS=\$(sudo docker ps -aq)

            echo "\$DOCKER_CONTAINER_IDS"
            for CONTAINER_ID in \$DOCKER_CONTAINER_IDS; do
                CONTAINER_NAME=\$(sudo docker inspect --format="{{.Name}}" "\$CONTAINER_ID" | sed 's/\///')

                sudo docker logs "\$CONTAINER_ID" &> "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt"

                aws s3 cp "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt" "s3://$S3_BUCKET/\$LOCAL_LOGS_DIR/storage/${node}/\$CONTAINER_NAME.txt"
            done
            rm -rf "\$LOCAL_LOGS_DIR"
            sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws awscliv2.zip aws
            "
        echo "done getting logs from node: ${node}"
    done
fi
