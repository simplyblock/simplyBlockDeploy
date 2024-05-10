## Prerequisites


Before deploying the infrastructure using Terraform, ensure that Terraform and AWS CLI are installed on your local machine. Also, configure AWS CLI with your AWS credentials.

### Installing Terraform

Follow the installation instructions for Terraform based on your operating system:

- [Terraform Installation Guide](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### Installing AWS CLI

Follow the installation instructions for AWS CLI based on your operating system:

- [AWS CLI Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

### Configuring AWS CLI

After installing AWS CLI, configure it with your AWS credentials by running the `aws configure` command and providing your Access Key ID, Secret Access Key, region, and output format.

### Intro



Terraform template to setup simple cluster

### Deploy infra

```
# change count for mgmt_nodes and storage_nodes variables in variables.tf

# review the resources
terraform init

### switch to workspace
terraform workspace select -or-create <workspace_name>

terraform plan

terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 --auto-approve

# Deploying with eks
terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 -var enable_eks=1 --auto-approve

# Specifying the instance types to use
terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 \
                -var mgmt_nodes_instance_type="m5.large" -var storage_nodes_instance_type="m5.large" --auto-approve

# Specifying the number of ebs volumes to attach to storage nodes
terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 -var volumes_per_storage_nodes=2 --auto-approve

# Specifying the size of ebs volumes for storage nodes
### -var storage_nodes_ebs_size1=2 for Journal Manaher
### -var storage_nodes_ebs_size2=50 for Storage node
terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 -var storage_nodes_ebs_size1=2 \
                -var storage_nodes_ebs_size2=50 for Storage node --auto-approve

# specifying the size of hugepage to use
terraform apply -var namespace="csi" -var mgmt_nodes=1 -var storage_nodes=3 -var nr_hugepages=2048 --auto-approve

# Save terraform output to a file
terraform output -json > outputs.json
```


### Cluster bootstrapping

```
# The boostrap-cluster.sh creates the KEY in `.ssh` directory in the home directory

chmod +x ./bootstrap-cluster.sh
./bootstrap-cluster.sh

# To see supported option
./bootstrap-cluster.sh --help

# specifying cluster argument to use
./bootstrap-cluster.sh --memory 8g --cpu-mask 0x3 --iobuf_small_pool_count 10000 --iobuf_large_pool_count 25000

# specifying the log deletion interval and metrics retention period
./bootstrap-cluster.sh --log-del-interval 30m --metrics-retention-period 2h
```

### Shutting Down and Restarting Cluster
##### shutdown
```
export $(xargs <local.env) && ./shutdown-restart.sh shutdown
```
##### restart
```
export $(xargs <local.env) && ./shutdown-restart.sh restart
```

### Destroy Cluster
```
terraform apply -var namespace="csi" -var mgmt_nodes=0 -var storage_nodes=0 --auto-approve
```

or you could destroy all the resources created
```
terraform destroy --auto-approve
```


create sn nodes of type: m6id.large
add sn to cluster --> wil get an error: nvme devices not found.

and change to i3en.large
we observe that the private IPs didn't change.
add sn to cluster  -->wil get an error: nvme devices not found.
