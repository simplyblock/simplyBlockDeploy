### Intro

Terraform template to setup simple cluster

### Deploy infra

```
# change count for mgmt_nodes and storage_nodes variables in variables.tf

terraform plan

# review the resources
terraform init
terraform apply -var mgmt_nodes=3 -var storage_nodes=3 --auto-approve
```

### Cluster bootstrapping

```
# in the boostrap-cluster.sh update KEY

chmod +x ./bootstrap-cluster.sh
./bootstrap-cluster.sh

```
