#!/bin/bash
namespace="alsh3test"
sbcli_pkg="sbcli-release"
spdk_image="simplyblock/spdk:faster-bdev-startup-latest"
#terraform destory --auto-approve

# review the resources
terraform init

### switch to workspace
terraform workspace select -or-create "$namespace"

terraform plan

# Specifying the instance types to use
terraform apply -var namespace="$namespace" -var mgmt_nodes=1 -var storage_nodes=3 -var extra_nodes=1 \
                -var mgmt_nodes_instance_type="m6i.xlarge" -var storage_nodes_instance_type="m5d.4xlarge" \
                -var extra_nodes_instance_type="m6i.xlarge" -var sbcli_pkg="$sbcli_pkg" \
                -var volumes_per_storage_nodes=0 -var region="eu-west-1" \
                --auto-approve

# Save terraform output to a file
terraform output -json > outputs.json

# The boostrap-cluster.sh creates the KEY in `.ssh` directory in the home directory

chmod +x ./bootstrap-cluster.sh
# specifying cluster argument to use
./bootstrap-cluster.sh --memory 16g --cpu-mask 0x3 --iobuf_small_pool_count 10000 --iobuf_large_pool_count 25000 \
                       --sbcli-cmd "$sbcli_pkg" --spdk-image "$spdk_image"

# specifying the log deletion interval and metrics retention period
./bootstrap-cluster.sh --log-del-interval 300m --metrics-retention-period 2h

# how can i increase root volume of mgmt node?
# how can i create client node? - clear

