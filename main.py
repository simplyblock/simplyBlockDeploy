import argparse
import sys
from simplyBlockDeploy.provisioner import provisioner
from simplyBlockDeploy.aws_functions import get_region_from_az
from simplyBlockDeploy.provisioner import provisioner, parse_instances_yaml

def check_namespace(namespace):
    if namespace.isalnum():
        return namespace

def main(argv):
    parser = argparse.ArgumentParser(description='Validate DNS-compliant name.')
    parser.add_argument('--namespace', type=check_namespace, required=True, help='DNS-compliant name')
    parser.add_argument('--az', type=get_region_from_az, required=True, help='Availability Zone name')
    parser.add_argument('--instance_yaml', type=parse_instances_yaml, required=True, help='Availability Zone name')
    parser.add_argument('--deploy', default=True, type=bool, required=False, help='Deploy SB if True')
    parser.add_argument('--dry-run', default=False, type=bool, required=False, help='Dry Run, only creates keys')
    args = parser.parse_args()
    provisioner(namespace=args.namespace, az=args.az, deploy=args.deploy, instances=args.instance_yaml)

if __name__ == "__main__":
   main(sys.argv[1:])