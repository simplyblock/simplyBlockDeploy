#!/bin/bash

KEY="$HOME/.ssh/simplyblock-ohio.pem"

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --sbcli-cmd <value>                  Set sbcli command name (optional, default: sbcli-dev)"
    echo "  --spdk-img <value>                   Set spdk image (optional)"
    echo "  --help                               Print this help message"
    exit 0
}

SBCLI_CMD="sbcli-dev"
SPDK_IMAGE=""
SHUTDOWN=false
RESTART=false

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        --sbcli-cmd)
            SBCLI_CMD="$2"
            shift
            ;;
        --spdk-image)
            SPDK_IMAGE="$2"
            shift
            ;;
        --shutdown)
            SHUTDOWN=true
            shift
            ;;
        --restart)
            RESTART=true
            shift
            ;;
        --help)
            print_help
            ;;
        *)
            echo "Unknown option: $1"
            print_help
            ;;
    esac
    shift
done

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
        echo "the ssh key: ${KEY} already exits on local"
    else
        echo "$SECRET_VALUE" >"$KEY"
        chmod 400 "$KEY"
    fi
else
    echo "Failed to retrieve secret value. Falling back to default key."
fi

mnodes=$(terraform output -raw mgmt_public_ips)

if [ "$SHUTDOWN" = true ]; then
    ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
    output_snode=\$(${SBCLI_CMD} storage-node list | awk 'NR>3')
    echo \"\$output_snode\" | awk 'BEGIN {FS = \"|\"} {gsub(/ /, \"\", \$2); gsub(/ /, \"\", \$9); print \$2, \$9}' | while read uuid ec2_id; do
        if [ -n \"\$uuid\" ] && [ -n \"\$ec2_id\" ]; then
        
            echo \"Suspending storage node with UUID: \$uuid\"
            ${SBCLI_CMD} storage-node suspend \"\$uuid\"

            echo \"Shutting down storage node with UUID: \$uuid\"
            ${SBCLI_CMD} storage-node shutdown \"\$uuid\"

            echo \"Shutting down EC2 instance: \$ec2_id\"
            aws ec2 stop-instances --instance-ids \"\$ec2_id\"
        fi
    done

    output_cluster=\$(${SBCLI_CMD} cluster list | awk 'NR>3')
    echo \"\$output_cluster\" | awk 'BEGIN {FS = \"|\"} {gsub(/ /, \"\", \$2); print \$2}' | while read uuid; do
        if [ -n \"\$uuid\" ]; then

            echo \"Suspending cluster with UUID: \$uuid\"
            ${SBCLI_CMD} cluster suspend \"\$uuid\"
        fi
    done
    "
elif [ "$RESTART" = true ]; then
    ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
    output_cluster=\$(${SBCLI_CMD} cluster list | awk 'NR>3')
    echo \"\$output_cluster\" | awk 'BEGIN {FS = \"|\"} {gsub(/ /, \"\", \$2); print \$2}' | while read uuid; do
        if [ -n \"\$uuid\" ]; then

            echo \"Unsuspending cluster with UUID: \$uuid\"
            ${SBCLI_CMD} cluster unsuspend \"\$uuid\"
        fi
    done

    output_snode=\$(${SBCLI_CMD} storage-node list | awk 'NR>3')
    echo \"\$output_snode\" | awk 'BEGIN {FS = \"|\"} {gsub(/ /, \"\", \$2); gsub(/ /, \"\", \$9); print \$2, \$9}' | while read uuid ec2_id; do
        if [ -n \"\$uuid\" ] && [ -n \"\$ec2_id\" ]; then

            echo \"Rebooting EC2 instance: \$ec2_id\"
            aws ec2 start-instances --instance-ids \"\$ec2_id\"
            sleep 10
            
            echo \"Restarting storage node with UUID: \$uuid\"
            ${SBCLI_CMD} storage-node restart \"\$uuid\"

        fi
    done
    "
fi