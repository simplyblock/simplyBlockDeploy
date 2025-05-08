#!/usr/bin/env python3

import argparse
import textwrap
import yaml


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('cluster', type=argparse.FileType('r'))
    args = parser.parse_args()

    cluster = yaml.safe_load(args.cluster)

    print(textwrap.dedent(f"""\
        export K3S_MNODES="{cluster['management_nodes'][0]}"
        export STORAGE_PRIVATE_IPS="{' '.join(cluster['storage_nodes'])}"
        export MNODES="{' '.join(cluster['management_nodes'])}"
        export API_INVOKE_URL="http://{cluster['management_nodes'][0]}/"
        export BASTION_IP="{cluster['management_nodes'][0]}"
        export MNODES="{cluster['management_nodes'][0]}"
        export GRAFANA_ENDPOINT="http://{cluster['management_nodes'][0]}/grafana\""""
    ))
