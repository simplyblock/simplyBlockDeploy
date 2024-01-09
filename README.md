### Intro

Terraform template to setup simple cluster

### Deploy infra

```
# change count for mgmt_nodes and storage_nodes variables in variables.tf

terraform plan

# review the resources

terraform apply
```

### Cluster bootstrapping

```
# in the boostrap-cluster.sh update KEY, mnodes, storage_private_ips

chmod +x ./bootstrap-cluster.sh
./bootstrap-cluster.sh

```
