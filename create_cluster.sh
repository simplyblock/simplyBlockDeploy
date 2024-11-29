#!/bin/bash

# CHANGE THE NAMESPACE NAME!
namespace="change_me"
sbcli_cmd="sbcli-dev"
CONTACT_POINT=<add_slack_webhook>


export TFSTATE_BUCKET=xata-simplyblock-staging-infra
export TFSTATE_KEY=staging/controlplane
export TFSTATE_REGION=us-east-2

terraform init -reconfigure \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="key=${TFSTATE_KEY}" \
    -backend-config="region=${TFSTATE_REGION}" \
    -backend-config="encrypt=true"

### switch to workspace
terraform workspace select -or-create "$namespace"

# terraform apply -var mgmt_nodes=1 -var storage_nodes=0 -var extra_nodes=0 --auto-approve

# Specifying the instance types to use
terraform apply -var mgmt_nodes=1 -var storage_nodes=4 -var extra_nodes=0 -var "storage_nodes_arch=arm64" \
                -var mgmt_nodes_instance_type="m6i.xlarge" -var storage_nodes_instance_type="c6gd.2xlarge" \
                -var extra_nodes_instance_type="m6i.large" -var sbcli_cmd="$sbcli_cmd" \
                -var volumes_per_storage_nodes=0 --auto-approve

# Save terraform output to a file
terraform output -json > tf_outputs.json

# The boostrap-cluster.sh creates the KEY in `.ssh` directory in the home directory

chmod +x ./bootstrap-cluster.sh
# specifying cluster argument to use
./bootstrap-cluster.sh --sbcli-cmd "$sbcli_cmd" --disable-ha-jm \
                       --distr-ndcs 2 --distr-npcs 1 --cap-crit 99 --cap-warn 94 --prov-cap-crit 500  \
                       --prov-cap-warn 200 --distr-bs 4096 --distr-chunk-bs 4096 \
                       --spdk-debug --max-lvol 200 --max-snap 200 --max-prov 10T --number-of-devices 1 \
                       --partitions 1 --log-del-interval 300m --metrics-retention-period 2h \
                       --number-of-distribs 2 \
                       --contact-point $CONTACT_POINT
