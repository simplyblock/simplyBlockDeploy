### Intro

Terraform template to setup simple cluster

### Deploy infra

```
# change count for mgmt_nodes and storage_nodes variables in variables.tf

# review the resources
terraform plan

terraform init
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 --auto-approve

# Deploying with eks and monitoring node
terraform init
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 enable_eks=1 monitoring_node=1 --auto-approve
```

### Cluster bootstrapping

```
# in the boostrap-cluster.sh update KEY

chmod +x ./bootstrap-cluster.sh
./bootstrap-cluster.sh

```
### Destroy Cluster
```
terraform apply -var mgmt_nodes=0 -var storage_nodes=0 --auto-approve
```


create sn nodes of type: m6id.large
add sn to cluster --> wil get an error: nvme devices not found.

and change to i3en.large
we observe that the private IPs didn't change.
add sn to cluster  -->wil get an error: nvme devices not found.
