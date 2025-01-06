#!/bin/bash
namespace="simplyblock"
sbcli_cmd="sbcli-dev"

export TFSTATE_BUCKET=qdrant-simplyblock-staging-infra
export TFSTATE_KEY=staging/controlplane
export TFSTATE_REGION=eu-central-1

terraform init -reconfigure \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="key=${TFSTATE_KEY}" \
    -backend-config="region=${TFSTATE_REGION}" \
    -backend-config="encrypt=true"

# terraform destroy --auto-approve
### switch to workspace
terraform workspace select -or-create "$namespace"

# terraform apply -target=module.vpc -var region=eu-central-1
# Specifying the instance types to use
terraform plan -var mgmt_nodes=1 -var storage_nodes=7 -var extra_nodes=0 -var "storage_nodes_arch=arm64" \
                -var mgmt_nodes_instance_type="m6i.xlarge" -var storage_nodes_instance_type="im4gn.4xlarge" \
                -var extra_nodes_instance_type="m6i.large" -var sbcli_cmd="sbcli-dev" \
                -var sec_storage_nodes=1 -var sec_storage_nodes_instance_type="m6g.4xlarge" \
                -var volumes_per_storage_nodes=0

terraform apply -var mgmt_nodes=1 -var storage_nodes=7 -var extra_nodes=0 -var "storage_nodes_arch=arm64" \
                -var mgmt_nodes_instance_type="m6i.xlarge" -var storage_nodes_instance_type="im4gn.4xlarge" \
                -var extra_nodes_instance_type="m6i.large" -var sbcli_cmd="sbcli-dev" \
                -var sec_storage_nodes=1 -var sec_storage_nodes_instance_type="m6g.4xlarge" \
                -var volumes_per_storage_nodes=0

# Save terraform output to a file
terraform output -json > tf_outputs.json

# The boostrap-cluster.sh creates the KEY in `.ssh` directory in the home directory

# chmod +x ./bootstrap-cluster.sh
# specifying cluster argument to use
# ./bootstrap-cluster.sh --sbcli-cmd "$sbcli_cmd" \
#                        --distr-ndcs 1 --distr-npcs 1 --cap-crit 99 --cap-warn 94 --prov-cap-crit 500  \
#                        --prov-cap-warn 200 --distr-bs 4096 --distr-chunk-bs 4096 \
#                        --spdk-debug --max-lvol 200 --max-snap 200 --max-prov 30T --number-of-devices 1 \
#                        --partitions 1 --log-del-interval 300m --metrics-retention-period 2h \
#                        --number-of-distribs 5
