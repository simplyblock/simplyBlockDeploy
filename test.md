`Simplyblock `deployment consists of three dependent parts (in that sequence):
* deploy the control plane (multiple storage clusters can connect)
* deploy the storage clusters (multiple k8s clusters can consume storage)
* deploy the CSI driver and (optionally) Caching Nodes

There are two ways to deploy the control plane and storage clusters:
* Use the deployment functions built into the simplyblock CLI
* Use the Simplyblock Auto-Deployer (currently only for AWS and not recommended for production)

The auto-deployer can be used to deploy EC2 and VPC infrastructure for the control plane and the storage clusters only (using terraform) or to deploy both infrastructure and clusters (control plane and storage nodes). See [here](https://github.com/simplyblock-io/simplyBlockDeploy.git).

## Manual Control Plane Deployment

The control plane can be deployed on one or three nodes. Currently, these nodes must run RHEL 9 or the rocky equivalent. Ensure the following network ports are open on the hosts and into or from the subnet:

| Service         | Direction | Source or target nw | ports |
| --------------- | --------- | ------------------- | ----- |
| API (http/s)    | ingress   | AWS API Gateway     | 80    |
| SSH             | ingress   | Bastion Server      | 22    |
| CLI             | ingress   | mgmt                | 2222  |
| grafana         | ingress   | AWS API Gateway     | 3000  |
| graylog         | ingress   | mgmt                | 9000  |
| prometheus      | ingress   | mgmt                | 9090  |
| docker swarm    | egress    | storage clusters,   | 2377, |
|                 |           | internal            | 7946, |
|                 |           |                     | 4789  |
| docker          | out       | registry            | 443   |
| SNodeAPI (http) | out       | storage clusters    | 80    |
| RPCs (http)     | out       | storage clusters    | 80    |
| dashboard       | in        | mgmt                | 8081  |
| HA-Proxy        | in        |                     | 8404  |

Important: on aws, API, grafana, graylog, HA-proxy, docker swarm dashboard and prometheus are accessible via API gateway. No specific ports need to be opened.

To deploy the control plane, first install the first node:

```
sudo yum -y install python3-pip
pip install sbcli-release --upgrade
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sbcli-release cluster create
sbcli-release cluster list
```
To install the second and third node:
```
sudo yum -y install python3-pip
pip install sbcli-release --upgrade
sbcli-release mgmt add <FIRST-MGMT-NODE-IP> <CLUSTER-UUID> eth0
```
To verify the mgmt domain is up and running, you may get the cluster secret (`sbcli-release cluster get-secret`) and log into the following services (use the external ip of any of the three nodes, for login to graylog, grafana and prometheus the user name is  admin and the password is the cluster secret, for the API, the cluster UUID and the secret are required):

| Service      | Port | User         | Secret         |
| ------------ | ---- | ------------ | -------------- |
| dashboard    | 8081 |              |                |
| API (http/s) | 443  | Cluster-UUID | cluster secret |
| grafana      | 3000 | admin        | cluster secret |
| graylog      | 9000 | admin        | cluster secret |
| HA-Proxy     | 8404 |              |                |
| prometheus   | 9090 | admin        | cluster secret |

Important: Accessibility on aws via API gateway

## Manual Storage Cluster Deployment

Storage nodes can be installed once the control plane is running.
The following ports must be opened within a storage cluster subnet:

| Service         | Direction | Source or target nw | ports |
| --------------- | --------- | ------------------- | ----- |
| docker swarm    | in, out   | control plane,      | 2377, |
|                 |           | internal            | 7946, |
|                 |           |                     | 4789  |
| docker          | out       | registry            | 443   |
| SNodeAPI (http) | in        | control plane       | 80    |
| RPCs (http)     | in        | control plane       | 80    |
| nvmf            | in        | k8s clusters        | 4420  |
|                 | out       | DR storage cluster  |       |

Storage nodes currenly also require `RHEL 9` or `Rocky 9`. Storage node installation consists of two parts. First, storage nodes are prepared for installation:

```
sudo yum -y install python3-pip
pip install sbcli-release --upgrade
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sbcli-release sn deploy
```
Copy information on ip address and port at which the storage node (sn) is listening.
Then **from one of the management nodes**, storage nodes must be added to the cluster via the CLI:
```
sbcli-release sn add
```
Description of parameters:

| Service      | Description                                       | Example                              |
| ------------ | ------------------------------------------------- | ------------------------------------ |
| UUID         | Cluster-UUID                                      | 8ce9b324-d3dc-488b-ad90-e88ec7e05ca3 |
| node-address | storage node IP and mgmt port (SNodeAPI listener) | 172:168.0.5:5000                     |
| CPU-mask     | CPU-cores to be used                              | 0xF (use first 4 cores)              |
| lvols        | Maximum lvols per node                            | 100                                  |
| snapshots    | Maximum active snapshots per lvol                 | 10                                   |

> [!IMPORTANT]
> the maximum amount of lvols and snapshots, depends on the available huge page and other system memory, also see [here](https://github.com/simplyblock-io/documentation/wiki/Deployment-Preparation#memory-requirements)
> the vcpus required depends on the expected IOPS and throughput, also see [here](https://github.com/simplyblock-io/documentation/wiki/Deployment-Preparation#vcpu-requirements)

## CSI Driver and Caching Node Deployment

The repository with the driver and documentation can be found [here ](https://github.com/simplyblock-io/spdk-csi/blob/master/README.md).




