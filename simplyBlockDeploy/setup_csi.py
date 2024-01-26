
from .fabric_functions import run_command_return_output
from jinja2 import Template
import pprint

def template_csi_yamls(cluster_data_for_csi_template):
    yaml_blob = str()
    yaml_list = [
        "config-map.yaml",
        "node.yaml",
        "controller-rbac.yaml",
        "nodeserver-config-map.yaml",
        "controller.yaml",
        "secret.yaml",
        "driver.yaml",
        "node-rbac.yaml",
        "storageclass.yaml"
    ]

    for yaml in yaml_list:
        yaml = "k8s-yaml/" + yaml
        with open(yaml, 'r') as file:
            yaml_blob = yaml_blob + file.read()

    j2_template = Template(yaml_blob)
    print(cluster_data_for_csi_template)
    return j2_template.render(cluster_data_for_csi_template)

def setup_csi(namespace=str, instances_dict_of_lists=None):

    def get_cluster_uuid(namespace=str, instance=str):
        # this file is there because I put it there during cluster setup.
        command = "sbcli cluster list | grep active | awk '{{print $2}}'"
        return run_command_return_output(namespace=namespace, host=instance, command=command)


    def get_cluster_secret(namespace=str, instance=str, cluster_uuid=str):
        command = "sbcli cluster get-secret {}".format(cluster_uuid)
        return run_command_return_output(namespace=namespace, host=instance, command=command)


    def kubectl_apply(namespace=str, instance=str, csi_yaml=str):
        command = """
kubectl apply -f - <<'EOF'
{}
EOF
        """.format(csi_yaml)
        return run_command_return_output(namespace=namespace, host=instance, command=command)
    

    def write_yamls(namespace=str, instance=str, csi_yaml=str):
        command = """
cat << 'EOF' > /tmp/yaml.yaml
{}
EOF
        """.format(csi_yaml)
        return run_command_return_output(namespace=namespace, host=instance, command=command)
    pp = pprint.PrettyPrinter(indent=4)
    pp.pprint(instances_dict_of_lists)

    management_node = instances_dict_of_lists["management"][0]
    kubernetes_node = instances_dict_of_lists["kubernetes"][0]

    cluster_uuid = get_cluster_uuid(namespace=namespace, instance=management_node.public_ip_address)
    cluster_secret = get_cluster_secret(namespace=namespace, instance=management_node.public_ip_address, cluster_uuid=cluster_uuid)

    # TODO: Decouple this mess. The values in this dicts are referenced in the yaml jinja2
    cluster_data_for_csi_template = {
        "cluster_uuid": cluster_uuid,
        "cluster_secret": cluster_secret,
        "cluster_master_private_ip": management_node.private_ip_address
    }
    print(cluster_data_for_csi_template)
    csi_yaml = template_csi_yamls(cluster_data_for_csi_template)
    print(csi_yaml)
    # TODO: templating yaml in python like this is abhorrent.
    write_yamls(namespace=namespace, instance=kubernetes_node.public_ip_address, csi_yaml=csi_yaml)
    kubectl_apply(namespace=namespace, instance=kubernetes_node.public_ip_address, csi_yaml=csi_yaml)
    

def main():
    setup_csi("defaultXYP", "eu-west-1", "keys/defaultXYP")

if __name__ == "__main__":
    main()



"""
    def do_api_things(host):
        with fabric.Connection('my-db-server').forward_local(5432):
            db = psycopg2.connect(
                host='localhost', port=5432, database='mydb'
            )
            # Do things with 'db' here
"""