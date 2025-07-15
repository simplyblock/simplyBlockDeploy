
# Prerequisites

Before deploying the infrastructure using Terraform, ensure that Terraform and AWS CLI are installed on your local machine. Also, configure AWS CLI with your AWS credentials.

## Installing Terraform

Follow the installation instructions for Terraform based on your operating system:

- [Terraform Installation Guide](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## Installing AWS CLI

Follow the installation instructions for AWS CLI based on your operating system:

- [AWS CLI Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

## Configuring AWS CLI

After installing AWS CLI, configure it with your AWS credentials by running the `aws configure` command and providing your Access Key ID, Secret Access Key, region, and output format.

# Deploy Infrastructure

## Change Node Counts

Modify the `mgmt_nodes` and `storage_nodes` variables in `variables.tf` as needed.

## Review the Resources

```bash
TFSTATE_BUCKET=simplyblock-terraform-state-bucket
TFSTATE_KEY=csi
TFSTATE_REGION=us-east-2
TFSTATE_DYNAMODB_TABLE=terraform-up-and-running-locks

terraform init -reconfigure \
    -backend-config="bucket=${TFSTATE_BUCKET}" \
    -backend-config="key=${TFSTATE_KEY}" \
    -backend-config="region=${TFSTATE_REGION}" \
    -backend-config="dynamodb_table=${TFSTATE_DYNAMODB_TABLE}" \
    -backend-config="encrypt=true"
```

## Switch to Workspace

```bash
terraform workspace select -or-create <workspace_name>
```

## Plan Deployment

```bash
terraform plan
```

> **Warning**
> Do not specify `-var region` during `terraform apply` but rather update the region default value in the `variable.tf` to avoid redundant resources.

## Apply Configurations

### Deploying with EKS

```bash
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 -var enable_eks=1 --auto-approve
```

### Specifying the AZ to Deploy

```bash
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 -var az=us-east-2b --auto-approve
```

### Specifying Instance Types

```bash
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 \
                -var mgmt_nodes_instance_type="m5.large" -var storage_nodes_instance_type="m5.large" --auto-approve
```

### Specifying the Size of EBS Volumes

```bash
# -var storage_nodes_ebs_size1=2 for Journal Manager
# -var storage_nodes_ebs_size2=50 for Storage node
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 -var storage_nodes_ebs_size1=2 \
                -var storage_nodes_ebs_size2=50 --auto-approve
```

### Specifying HugePage Size

```bash
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 -var nr_hugepages=2048 --auto-approve
```

### Using Dev or Prod TFVars

```bash
terraform apply -var-file="dev.tfvars" --auto-approve
```

### Specifying the Number of Secondary Storage node and Instance Type

```bash
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 \
                -var sec_storage_nodes=1 -var sec_storage_nodes_instance_type="m5.large" --auto-approve
```

### Specifying the parameters for Storage node Configuration 

```bash
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 \
                -var max_lvol=20 -var max_size="200G" -var nodes_per_socket=1 \
                -var socket_to_use="0" -var 'pci_allowed=[""]' -var 'pci_blocked==[""]' --auto-approve
```

### Save Terraform Output to a File

```bash
terraform output -json > outputs.json
```

# Cluster Bootstrapping

## Bootstrap Script

```bash
# The bootstrap-cluster.sh creates the KEY in `.ssh` directory in the home directory
chmod +x ./bootstrap-cluster.sh
./bootstrap-cluster.sh
```

### View Supported Options

```bash
./bootstrap-cluster.sh --help
```

### Specifying Cluster Arguments

# specifying cluster argument to use
./bootstrap-cluster.sh --max-lvol 10 --max-snap 10 --max-prov 150g

### Specifying Log Deletion Interval, Metrics Retention Period and Contact Point


```bash
./bootstrap-cluster.sh --log-del-interval 30m --metrics-retention-period 2h --contact-point <slack webhook>
```

### Deploy Storage-node to K8s

#### Set cluster argument --k8s-snode

```bash
./bootstrap-cluster.sh --k8s-snode
```


#### Set k3s argument --k8s-snode

```bash
./bootstrap-k3s.sh --k8s-snode
```

# Shutting Down and Restarting Cluster

## Add Variables to local.env File

```bash
API_INVOKE_URL=https://x8dg1t0y1k.execute-api.us-east-2.amazonaws.com
CLUSTER_ID=10b8b609-7b28-4797-a3a1-0a64fed1fad2
CLUSTER_SECRET=I7U9C0daZ64RsxmNG4NK
```

## Shutdown

```bash
export $(xargs <local.env) && ./shutdown-restart.sh shutdown
```

## Restart

```bash
export $(xargs <local.env) && ./shutdown-restart.sh restart
```

# Destroy Cluster

```bash
terraform apply -var mgmt_nodes=0 -var storage_nodes=0 --auto-approve
```

or you could destroy all the resources created

```bash
terraform destroy --auto-approve
```

# SSH to Cluster using Bastion

## Assuming the Following

Key pair file name: simplyblock-us-east-1.pem

### Step

Use this command to SSH into the management node or storage nodes in private subnets:

```bash
ssh -i ~/.ssh/simplyblock-us-east-1.pem -o ProxyCommand="ssh -i ~/.ssh/simplyblock-us-east-1.pem -W %h:%p ec2-user@<Bastion-Public-IP>" ec2-user@<Management-Node-Private-IP or Storage-Node-Private-IP>
```

### Connecting using SSM Session Manager

please make sure that [session manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-macos-overview.html) is installed

start session by running

```
aws ssm start-session --target i-040f2ed69d42bcabc
```
