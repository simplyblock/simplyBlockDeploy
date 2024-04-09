### Intro

Terraform template to setup simple cluster

### Deploy infra

```
# change count for mgmt_nodes and storage_nodes variables in variables.tf

# review the resources
terraform plan

terraform init

terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 --auto-approve

# Deploying with eks
terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 -var enable_eks=1 --auto-approve

# Specifying the instance types to use 
terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 \
                -var mgmt_nodes_instance_type="m5.large" -var storage_nodes_instance_type="m5.large" --auto-approve

# Specifying the size of ebs volumes for storage nodes
terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 -var storage_nodes_ebs_size=50 --auto-approve
```

### Cluster bootstrapping

```
# The boostrap-cluster.sh creates the KEY in `.ssh` directory in the home directory

chmod +x ./bootstrap-cluster.sh
./bootstrap-cluster.sh

# specifying cluster argument to use
./bootstrap-cluster.sh --memory 8g --cpu-mask 0x3 --iobuf_small_pool_count 10000 --iobuf_large_pool_count 25000
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
