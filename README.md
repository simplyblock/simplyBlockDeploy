# simplyBlockDeploy

## Deploying Simplyblock cluster.

Clone the repo and cd into the dir.

Make venv

`python3 -m venv .venv`
`. .venv/bin/activate`

Adjust node number and types in `--instance_yaml` file and deploy.

`python main.py --namespace <namespace> --az <az> --instance_yaml 3-master-3-node.yaml`

Wait for the cluster to set up. Then Log in to one of the nodes:

`ssh keys/<namespace> rocky@<ip>`

Note: `<namespace>` must be alphanumeric with no blank or special characters.

## Mechanics

This script works by:

* importing node configurations from a yaml file specified with `--instance_yaml`
* creating a cloudformation tempate with `simplyBlockDeploy/cf_construct.py`
* sending that template to aws with the `cloudformation_deploy` function in `simplyBlockDeploy/aws_functions.py`
* discovering the instances that resulted from the cloudformation with the `get_instances_from_cf_resources` function in `simplyBlockDeploy/aws_functions.
* connecting to them and deploying the stack using [Fabric](https://www.fabfile.org/).

## Kubernetes

This script will deploy a k3s kubernetes node and will set up the CSI driver automatically with `setup_csi.py`. 

## SSH Keys

This script generates ssh keys which are placed in keys/<namespace>. Changing permisisons of keys in python is annoying so you'll need to `chmod 600 keys/<namespace>` the first time the key is generated. 

## namespaces
Namespaces are used to create resources on AWS. Namespaces must be distinct within AWS regions. You can reuse namespaces if you delete the cloudformation stack in the AWS console.

## Cleaning up

Delete the stack in the cloudformation page of the aws console and everything will be cleaned up.

eu-west-1 region: [https://eu-west-1.console.aws.amazon.com/cloudformation](https://eu-west-1.console.aws.amazon.com/cloudformation)