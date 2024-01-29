# sbDeploy

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
