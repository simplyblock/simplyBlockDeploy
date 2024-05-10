#!/bin/bash

print_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo " shutdown                           Set for cluster shutdown (optional)"
    echo " restart                            Set fot cluster restart (optional)"
    echo " help                               Print this help message"
    exit 0
}

SHUTDOWN=false
RESTART=false

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        shutdown)
            SHUTDOWN=true
            shift
            ;;
        restart)
            RESTART=true
            shift
            ;;
        help)
            print_help
            ;;
        *)
            echo "Unknown option: $1"
            print_help
            ;;
    esac
    shift
done

if [ "$SHUTDOWN" = true ]; then
    curl -X PUT $API_INVOKE_URL/cluster/gracefulshutdown/$CLUSTER_ID \
                --header "Content-Type: application/json" \
                --header "Authorization: $CLUSTER_ID $CLUSTER_SECRET"

    sleep 20

    ec2_instance_ids=$(curl -X GET "$API_INVOKE_URL/storagenode" \
                            --header "Content-Type: application/json" \
                            --header "Authorization: $CLUSTER_ID $CLUSTER_SECRET" \
                            | jq -r '.results[].ec2_instance_id')

    echo "$ec2_instance_ids" | while read -r instance_id; do
        if [ -n "$instance_id" ]; then
            echo "Shutting down EC2 instance: $instance_id"
            aws ec2 stop-instances --instance-ids "$instance_id"
        fi
    done

elif [ "$RESTART" = true ]; then
    ec2_instance_ids=$(curl -X GET "$API_INVOKE_URL/storagenode" \
                            --header "Content-Type: application/json" \
                            --header "Authorization: $CLUSTER_ID $CLUSTER_SECRET" \
                            | jq -r '.results[].ec2_instance_id')

    echo "$ec2_instance_ids" | while read -r instance_id; do
        if [ -n "$instance_id" ]; then
            echo "Starting EC2 instance: $instance_id"
            aws ec2 start-instances --instance-ids "$instance_id"
        fi
    done
    sleep 20
    
    curl -X PUT $API_INVOKE_URL/cluster/gracefulstartup/$CLUSTER_ID \
                --header "Content-Type: application/json" \
                --header "Authorization: $CLUSTER_ID $CLUSTER_SECRET"
fi
