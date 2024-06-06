#!/bin/bash
namespace="israel"
sbcli_pkg="sbcli-mc"
sbcli_cmd="sbcli-mc"
spdk_image="simplyblock/spdk:faster-bdev-startup-latest"


### switch to workspace
terraform workspace select -or-create "$namespace"

# review the resources
terraform destroy --auto-approve
# review the resources
terraform init -reconfigure
terraform plan

#-var region="eu-west-1" --iobuf_large_pool_count 16384 --iobuf_small_pool_count 131072 \
# Specifying the instance types to use
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 -var extra_nodes=1 \
                -var mgmt_nodes_instance_type="m6i.xlarge" -var storage_nodes_instance_type="m6i.large" \
                -var extra_nodes_instance_type="m6i.large" -var sbcli_pkg="$sbcli_pkg" \
                -var volumes_per_storage_nodes=2 -var region="eu-west-1" \
                --auto-approve

# Save terraform output to a file
terraform output -json > 842_outputs.json

# The boostrap-cluster.sh creates the KEY in `.ssh` directory in the home directory

chmod +x ./bootstrap-cluster.sh
# specifying cluster argument to use
# --iobuf_small_pool_count 10000 --iobuf_large_pool_count 25000 \
# --iobuf_large_pool_count 16384 --iobuf_small_pool_count 131072
./bootstrap-cluster.sh --memory 16g  --cpu-mask 0x3 \
                       --sbcli-cmd "$sbcli_cmd" --spdk-image "$spdk_image" \
                       --iobuf_large_pool_count 16384 --iobuf_small_pool_count 131072 \
                       --log-del-interval 300m --metrics-retention-period 2h
