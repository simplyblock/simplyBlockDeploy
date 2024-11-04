#!/bin/bash
namespace="simplyblock"
sbcli_pkg="sbcli-pre"
spdk_image="simplyblock/spdk:faster-bdev-startup-latest"
#terraform destroy --auto-approve

# review the resources


export TFSTATE_BUCKET=qdrant-simplyblock-staging-infra
export TFSTATE_KEY=staging/controlplane
export TFSTATE_REGION=us-east-2

terraform init -reconfigure \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="key=${TFSTATE_KEY}" \
    -backend-config="region=${TFSTATE_REGION}" \
    -backend-config="encrypt=true"

### switch to workspace
terraform workspace select -or-create "$namespace"

terraform plan

# create initial infra
terraform apply -var mgmt_nodes=0 -var storage_nodes=0 -var extra_nodes=0 \
                 -var mgmt_nodes_instance_type="m6i.xlarge" -var storage_nodes_instance_type="i3en.6xlarge" \
                 -var sbcli_cmd="sbcli-pre" -var extra_nodes_instance_type=m6gd.xlarge \
                 -var volumes_per_storage_nodes=0 -var region=eu-central-1 -var extra_nodes_arch=arm64


# Specifying the instance types to use
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 -var extra_nodes=1 \
                 -var mgmt_nodes_instance_type="m6i.xlarge" -var storage_nodes_instance_type="i3en.6xlarge" \
                 -var sbcli_cmd="sbcli-pre" -var extra_nodes_instance_type=c6gd.8xlarge \
                 -var volumes_per_storage_nodes=0 -var region=eu-central-1 -var extra_nodes_arch=arm64

# Save terraform output to a file
terraform output -json > outputs.json

# The boostrap-cluster.sh creates the KEY in `.ssh` directory in the home directory

chmod +x ./bootstrap-cluster.sh
# specifying cluster argument to use
# --iobuf_small_pool_count 10000 --iobuf_large_pool_count 25000 \
# --iobuf_large_pool_count 16384 --iobuf_small_pool_count 131072
./bootstrap-cluster.sh --memory 16g  --cpu-mask 0x3 \
                       --sbcli-cmd "$sbcli_pkg" --spdk-image "$spdk_image" \
                       --iobuf_large_pool_count 16384 --iobuf_small_pool_count 131072 \
                       --log-del-interval 300m --metrics-retention-period 2h
