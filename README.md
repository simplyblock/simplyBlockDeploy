# sbDeploy

## Deploying Simplyblock cluster.

Clone the repo and cd into the dir.

Make venv

`python3 -m venv .venv`
`. .venv/bin/activate`

Adjust node number and types in instances.yaml and deploy.

`python main.py --namespace andrew3 --az eu-west-1a --instance_yaml 3-master-3-node.yaml`