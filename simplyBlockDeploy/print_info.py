import yaml

def convert_boto_instance_to_dict(instance):
    _instance = {}
    _instance["tags"] = instance.tags
    _instance["instance_type"] = instance.instance_type
    _instance["block_device_mappings"] = instance.block_device_mappings
    _instance["instance_id"] = instance.instance_id
    _instance["private_ip_address"] = instance.private_ip_address
    _instance["public_ip_address"] = instance.public_ip_address
    _instance["state"] = instance.state
    return _instance

def print_info(instances=None):
    all_instances = []
    for instance in instances['all_instances']:
        all_instances.append(convert_boto_instance_to_dict(instance))
    print(yaml.dump(all_instances))





