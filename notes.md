# with create cluster

By default it uses the key `~/.ssh/id_ed25519`. You would like to use a seperate key. They needs to be passed seperately in terraform variable and script

intialize the state
```
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
create a workspace

```
terraform workspace -or-create <workspace-name>
```

### Provision infra
```
terraform apply -var mgmt_nodes=1 -var storage_nodes=3 -var extra_nodes=1 -var sbcli_cmd=sbcli-rj -var storage_nodes_distro=rhel9
```

### create mgmt cluster on docker 
```
./bootstrap-cluster.sh --max-lvol 50 --max-snap 10 --sbcli-cmd sbcli-rj --k8s-snode
```

### setup k3s based k8s cluster [can be parallel]
```
./bootstrap-k3s.sh --k8s-snode
```

### [OR] setup talos base k8s cluster
```
TODO
```

### Add storage nodes
```
./storagenodes-k8s.sh
```


### ssh into nodes
export BATIONIP=18.216.190.237
export KEY=~/.ssh/id_ed25519
```
ssh -i $KEY -o StrictHostKeyChecking=no -o 'ProxyCommand=ssh -o StrictHostKeyChecking=no -i $KEY -W %h:%p ec2-user@$BASTIONIP' ec2-user@10.0.3.82
```
