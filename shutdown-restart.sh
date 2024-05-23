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

    echo "Initiated cluster shutdown. Waiting for storage nodes to go offline..."

    all_nodes_offline=false
    while [ "$all_nodes_offline" = false ]; do
        node_status=$(curl -X GET "$API_INVOKE_URL/storagenode" \
                           --header "Content-Type: application/json" \
                           --header "Authorization: $CLUSTER_ID $CLUSTER_SECRET" \
                           | jq -r '.results[].status')

        echo "$node_status"

        all_nodes_offline=true
        for status in $node_status; do
            if [ "$status" != "offline" ]; then
                all_nodes_offline=false
                echo "Waiting for all storage nodes to go offline..."
                break
            fi
        done
    done

    echo "All storage nodes are offline. Proceeding with EC2 instance shutdown..."

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

    echo "Initiated cluster startup..."

    all_nodes_online=false
    while [ "$all_nodes_online" = false ]; do
        node_status=$(curl -X GET "$API_INVOKE_URL/storagenode" \
                           --header "Content-Type: application/json" \
                           --header "Authorization: $CLUSTER_ID $CLUSTER_SECRET" \
                           | jq -r '.results[].status')

        echo "$node_status"

        all_nodes_online=true
        for status in $node_status; do
            if [ "$status" != "online" ]; then
                all_nodes_online=false
                echo "Waiting for all storage nodes to be online..."
                break
            fi
        done
    done

    echo "All storage nodes are online now..."

fi
