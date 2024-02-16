import yaml
import json

from .ssh_tunnels import create_ssh_tunnel
from .ssh_keys import generate_create_ssh_keypair
from .cf_construct import cf_construct
from .aws_functions import cloudformation_deploy, get_instances_from_cf_resources
from .sb_deploy import sb_deploy
from .print_info import print_info, print_connectivity_info
from .setup_csi import setup_csi


def parse_instances_yaml(instances_yaml_file):
    with open(instances_yaml_file, "r") as stream:
        try:
            instances = yaml.safe_load(stream)
        except yaml.YAMLError as exc:
            print(exc)
            raise

        for instance in instances.get("instances", {}):
            if instance["Role"] == "management" and instance["SubnetId"] == "PublicSubnet":
                break
        else:
            print("At least one management node must be in PublicSubnet")
            raise Exception("At least one management node must be in PublicSubnet")
    return instances


def ensure_instance_ssh_connectivity(namespace, instances):
    def filter_instance_by_role_key(role):
        return list(
            filter(lambda instance: any(tag['Key'] == 'Role' and tag['Value'] == role for tag in instance.tags or []),
                   instances)
        )

    instances_dict = {
        "all_instances": instances,
        "storage": filter_instance_by_role_key("storage"),
        "management": filter_instance_by_role_key("management"),
        "kubernetes": filter_instance_by_role_key("kubernetes")
    }

    public_ip = [i.public_ip_address for i in instances_dict['management'] if i.public_ip_address][0]
    remote_hosts = []
    local_ports = []
    local_port = 8022
    for instance in instances:
        if instance.public_ip_address:
            instance.ssh_host_port = instance.public_ip_address
        else:
            remote_hosts.append(instance.private_ip_address)
            local_ports.append(local_port)
            instance.ssh_host_port = f"localhost:{local_port}"
            print(f"Create tunnel: localhost:{local_port} <-> {instance.private_ip_address}:22")
            local_port += 1

    if remote_hosts:
        create_ssh_tunnel(namespace, local_ports, remote_hosts, public_ip)
    return instances_dict


def provisioner(namespace=None, az=None, deploy=None, instances=None, dry_run=False, sbcli_pkg=None):
    # Set up key filename
    instances['PublicKeyMaterial'] = generate_create_ssh_keypair(namespace=namespace)

    # Get the CF stack
    cf_stack = cf_construct(namespace=namespace, instances=instances, region=az)
    print(json.dumps(cf_stack, indent=4))
    if dry_run or not deploy:
        print("Dry run! No deployment done.")
        return

    # cloudformation will deploy and return when the stack is green.
    # If the stack is already deployed in that namespace it will catch the error and return.
    stack_id = cloudformation_deploy(namespace=namespace, cf_stack=cf_stack, region_name=az["RegionName"])
    if not stack_id:
        return

    instances_list = get_instances_from_cf_resources(namespace=namespace, region_name=az['RegionName'])
    instances_dict_of_lists = ensure_instance_ssh_connectivity(namespace, instances_list)
    cluster_create_output = sb_deploy(namespace=namespace, instances=instances_dict_of_lists, sbcli_pkg=sbcli_pkg)

    if instances_dict_of_lists["kubernetes"]:
        from pkg_resources import Requirement
        sbcli_cmd = Requirement.parse(sbcli_pkg).name
        setup_csi(namespace=namespace, instances_dict_of_lists=instances_dict_of_lists,
                  cluster_uuid=cluster_create_output["cluster_uuid"], sbcli_cmd=sbcli_cmd)
    else:
        print("Kubernetes nodes are not defined. Csi setup skipped.")
    print_info(instances_dict_of_lists)
    print_connectivity_info(instances_dict_of_lists, namespace)
