import yaml
import json
from .ssh_keys import generate_create_ssh_keypair
from .cf_construct import cf_construct
from .aws_functions import cloudformation_deploy


def parse_instances_yaml(instances_yaml_file):
    with open(instances_yaml_file, "r") as stream:
        try:
            instances = yaml.safe_load(stream)
        except yaml.YAMLError as exc:
            print(exc)
    return instances

def provisioner(namespace="default", az="az", deploy=True, instances=None):
    # Set up key filename
    key_filename = "keys/{}".format(namespace)
    instances['PublicKeyMaterial'] = generate_create_ssh_keypair(key_filename=key_filename)
    cf_stack = cf_construct(namespace=namespace, instances=instances, region=az)
    print(json.dumps(cf_stack, indent=4))
    cloudformation_deploy(namespace=namespace, cf_stack=cf_stack, region=az["RegionName"])
