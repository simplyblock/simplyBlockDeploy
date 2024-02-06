import argparse
import sys
from simplyBlockDeploy.aws_functions import get_region_from_az
from simplyBlockDeploy.provisioner import provisioner, parse_instances_yaml


def check_namespace(namespace):
    if namespace.isalnum():
        return namespace
    else:
        raise Exception("namespace must be in alphanumeric format")


def main(argv):
    parser = argparse.ArgumentParser(description='Validate DNS-compliant name.')
    parser.add_argument('--namespace', type=check_namespace, required=True, help='DNS-compliant name')
    parser.add_argument('--az', type=get_region_from_az, required=True, help='Availability Zone name')
    parser.add_argument('--instance_yaml', type=parse_instances_yaml, required=True,
                        help='Availability Zone name')
    parser.add_argument('--dry-run', dest='dry_run', action='store_true',
                        help='Dry Run, only creates keys')
    parser.add_argument('--sbcli-pkg', default='sbcli', required=False, dest='sbcli_pkg',
                        help='sbcli requirement specifier for "pip install" (e.g. "sbcli-release", "sbcli-dev")')

    # TODO: delete if not used
    parser.add_argument('--deploy', default=True, type=bool, required=False,
                        help='Obsolete. Should not be used.')

    args = parser.parse_args()
    provisioner(namespace=args.namespace, az=args.az, deploy=args.deploy, instances=args.instance_yaml,
                dry_run=args.dry_run, sbcli_pkg=args.sbcli_pkg)


if __name__ == "__main__":
    main(sys.argv[1:])
