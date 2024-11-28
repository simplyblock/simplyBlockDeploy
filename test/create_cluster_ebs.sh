#!/bin/bash

# CHANGE THE NAMESPACE NAME!
namespace="changeme"
sbcli_cmd="sbcli-dev"


export TFSTATE_BUCKET=xata-simplyblock-staging-infra
export TFSTATE_KEY=staging/controlplane
export TFSTATE_REGION=us-east-2

terraform init -reconfigure \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="key=${TFSTATE_KEY}" \
    -backend-config="region=${TFSTATE_REGION}" \
    -backend-config="encrypt=true"

### switch to workspace
terraform destroy --auto-approve
terraform workspace select -or-create "$namespace"

# terraform apply -var mgmt_nodes=1 -var storage_nodes=0 -var extra_nodes=0 --auto-approve

# Specifying the instance types to use
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 -var extra_nodes=0 \
                -var mgmt_nodes_instance_type="m6i.xlarge" -var storage_nodes_instance_type="m6i.2xlarge" \
                -var extra_nodes_instance_type="m6i.large" -var sbcli_cmd="$sbcli_cmd" \
                -var volumes_per_storage_nodes=3 -var storage_nodes_ebs_size2=100 --auto-approve

# Save terraform output to a file
terraform output -json > tf_outputs.json

# The boostrap-cluster.sh creates the KEY in `.ssh` directory in the home directory

chmod +x ./bootstrap-cluster.sh
# specifying cluster argument to use
./bootstrap-cluster.sh --sbcli-cmd "$sbcli_cmd"  --spdk-debug \
                       --max-lvol 10 --max-snap 10 --max-prov 1200G \
                       --number-of-devices 3 --log-del-interval 900m --metrics-retention-period 2h \
                       --distr-ndcs 2 --distr-npcs 1 --distr-bs 4096 --distr-chunk-bs 4096 --partitions 0
