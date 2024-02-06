import yaml


def convert_boto_instance_to_dict(instance):
    _instance = {
        "tags": instance.tags,
        "instance_type": instance.instance_type,
        "block_device_mappings": instance.block_device_mappings,
        "instance_id": instance.instance_id,
        "private_ip_address": instance.private_ip_address,
        "public_ip_address": instance.public_ip_address,
        "state": instance.state,
        "public_dns_name": instance.public_dns_name
    }
    return _instance


def print_info(instances=None):
    all_instances = []
    for instance in instances['all_instances']:
        all_instances.append(convert_boto_instance_to_dict(instance))
    print(yaml.dump(all_instances))


def print_connectivity_info(instances, namespace):
    private_key_path = "keys/{}".format(namespace)
    instance_dict = {}
    print("Brief connectivity info:")
    for role in ("storage", "management", "kubernetes"):
        instance_dict[role] = [f"ssh -i {private_key_path} rocky@{instance.public_dns_name}"
                               for instance in instances[role]]

    print(yaml.dump(instance_dict))
