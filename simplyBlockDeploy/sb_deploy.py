from .fabric_functions import run_concurrent_command

def sb_deploy(namespace=None, instances=None):
    print("Depoying SimplyBlock Software. Namespace is {}".format(namespace))

    def install_deps(instance_list=None, namespace=namespace):
        command = """
            sudo yum update -y
            sudo yum install -y pip fio nvme-cli
            sudo pip install sbcli
            pip install sbcli==4.4.0
            sudo modprobe nvme-tcp
        """
        run_concurrent_command(namespace=namespace, instance_list=instance_list, command=command)

    def sbcli_storage_node_deploy(instance_list=None, namespace=namespace):
        command = """
            sbcli storage-node deploy
        """
        run_concurrent_command(namespace=namespace, instance_list=instance_list, command=command)

    def sbcli_cluster_create(instance_list=None, namespace=namespace):
        command = """
            sudo yum install -y fio nvme-cli
            sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
            sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
            sbcli cluster create --model_ids 'Amazon Elastic Block Store'
            sbcli cluster list
        """
        run_concurrent_command(namespace=namespace, instance_list=instance_list, command=command)

    def sbcli_storage_node_add_node(instance_list=None, storage_instances_private=None, namespace=namespace):
        command_list = []
        for instance in storage_instances_private:
            command_list.append("""
            sbcli cluster list | grep active | awk '{{print $2}}' > cluster_uuid
            sbcli storage-node add-node \
            --cpu-mask 0x3 --memory 16g \
            --bdev_io_pool_size 10000 \
            --bdev_io_cache_size 10000 \
            --iobuf_small_cache_size 10000 \
            --iobuf_large_cache_size 25000 \
            $(cat cluster_uuid) {}:5000 eth0
        """.format(instance))
            # print(command)
        command_list.append("sbcli pool add pool1")
        command = "".join(command_list)
        run_concurrent_command(namespace=namespace, instance_list=instance_list, command=command)

    def k8s_cluster_create(instance_list=None, namespace=namespace):
        command = """
        sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
        curl -sfL https://get.k3s.io | sh -
        sleep 60
        sudo chmod 777 /etc/rancher/k3s/k3s.yaml
        k3s kubectl get node
        """
        run_concurrent_command(namespace=namespace, instance_list=instance_list, command=command)

    all_instances = [i.public_ip_address for i in instances['all_instances']]
    storage_instances = [i.public_ip_address for i in instances['storage']]
    storage_instances_private = [i.private_ip_address for i in instances['storage']]
    management_instances = [i.public_ip_address for i in instances['management']]
    kubernetes_instances = [i.public_ip_address for i in instances['kubernetes']]

    install_deps(instance_list=all_instances, namespace=namespace)
    sbcli_storage_node_deploy(instance_list=storage_instances, namespace=namespace)
    sbcli_cluster_create(instance_list=management_instances, namespace=namespace)
    sbcli_storage_node_add_node(instance_list=management_instances, storage_instances_private=storage_instances_private, namespace=namespace)
    k8s_cluster_create(instance_list=kubernetes_instances, namespace=namespace)