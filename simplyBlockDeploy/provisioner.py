import yaml
import json
from .ssh_keys import generate_create_ssh_keypair
from .cf_construct import cf_construct
from .aws_functions import cloudformation_deploy, get_instances_from_cf_resources
from .sb_deploy import sb_deploy
from .print_info import print_info
import pprint


def parse_instances_yaml(instances_yaml_file):
    with open(instances_yaml_file, "r") as stream:
        try:
            instances = yaml.safe_load(stream)
        except yaml.YAMLError as exc:
            print(exc)
    return instances


def provisioner(namespace=None, az=None, deploy=None, instances=None):
    # Set up key filename
    instances['PublicKeyMaterial'] = generate_create_ssh_keypair(namespace=namespace)
    # Get the CF stack
    cf_stack = cf_construct(namespace=namespace, instances=instances, region=az)
    # cloudformation will deploy and return when the stack is green. 
    # If the stack is already deployed in that namespace it will catch the error and return.
    # cloudformation_deploy(namespace=namespace, cf_stack=cf_stack, region_name=az["RegionName"])
    instances_dict_of_lists = get_instances_from_cf_resources(namespace=namespace, region_name=az['RegionName'])
    sb_deploy(namespace=namespace, instances=instances_dict_of_lists)
    # print_info(instances_dict_of_lists)
