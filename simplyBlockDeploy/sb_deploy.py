from .fabric_functions import run_concurrent_command, run_command_return_output
from pkg_resources import Requirement


def sb_deploy(namespace=None, instances=None, sbcli_pkg="sbcli"):
    print("Deploying SimplyBlock Software. Namespace is {}".format(namespace))
    sbcli_cmd = Requirement.parse(sbcli_pkg).name

    def install_deps(instance_list=None):
        command = f"""
            sudo yum update -y
            sudo yum install -y pip fio nvme-cli
            sudo pip install {sbcli_pkg}
            sudo modprobe nvme-tcp
        """
        run_concurrent_command(namespace=namespace, instance_list=instance_list, command=command)

    def sbcli_storage_node_deploy(instance_list=None, namespace=namespace):
        command = f"""
            {sbcli_cmd} storage-node deploy
        """
        run_concurrent_command(namespace=namespace, instance_list=instance_list, command=command)

    def sbcli_cluster_create(instance_list_public=None, instance_list_private=None, namespace=namespace):
        first_master_created = False
        cluster_uuid = None
        management_master_private = None
        management_master_public = None
        for instance_public, instance_private in zip(instance_list_public, instance_list_private):
            print("first_master_created:{}".format(first_master_created))
            print("cluster_uuid:{}".format(cluster_uuid))
            if cluster_uuid is None:
                command = f"""
                    set x
                    sudo yum install -y fio nvme-cli
                    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
                    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
                    {sbcli_cmd} cluster create --model_ids 'Amazon Elastic Block Store'
                    {sbcli_cmd} cluster list | grep active | awk '{{{{print $2}}}}' > cluster_uuid
                    echo "Cluster $(cat cluster_uuid) ready on $(hostname)"
                    sleep 180
                """
                run_command_return_output(namespace=namespace, machine=instance_public, command=command)

                command = """
                    cat cluster_uuid
                """
                
                cluster_uuid = run_command_return_output(namespace=namespace, machine=instance_public, command=command).strip()
                management_master_private = instance_private
                management_master_public = instance_public
            else:
                command = f"""
                    set -x
                    hostname
                    sudo yum install -y fio nvme-cli
                    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
                    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
                    echo $(hostname) ready to be added to cluster {cluster_uuid} on ip {management_master_private}
                    {sbcli_cmd} mgmt add {management_master_private} {cluster_uuid} eth0
                """
                run_command_return_output(namespace=namespace, machine=instance_public, command=command)
        return {
            "cluster_uuid": cluster_uuid,
            "management_master_public": management_master_public 
        }


    def sbcli_storage_node_add_node(cluster_create_output=None, storage_instances_private=None, namespace=None):
        command_list = []
        for storage_instance in storage_instances_private:
            command_list.append(f"""
            set -x
            hostname
            {sbcli_cmd} cluster list | grep active | awk '{{{{print $2}}}}' > cluster_uuid
            {sbcli_cmd} storage-node add-node \
            --cpu-mask 0x3 --memory 16g \
            --bdev_io_pool_size 10000 \
            --bdev_io_cache_size 10000 \
            --iobuf_small_cache_size 10000 \
            --iobuf_large_cache_size 25000 \
            {cluster_create_output["cluster_uuid"]} {storage_instance}:5000 eth0
            sleep 10
            echo '## {sbcli_cmd} cluster list ##'
            {sbcli_cmd} cluster list
            echo '## {sbcli_cmd} storage-node list ##'
            {sbcli_cmd} storage-node list
            """)
            # print(command)
        command_list.append(f"{sbcli_cmd} pool add pool1")
        command = "".join(command_list)
        run_command_return_output(namespace=namespace, machine=cluster_create_output["management_master_public"], command=command)
        # run_concurrent_command(namespace=namespace, instance_list=instance_list, command=command)

    def k8s_cluster_create(instance_list=None, namespace=namespace):
        command = """
        set -x
        sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
        curl -sfL https://get.k3s.io | sh -
        sleep 60
        sudo chmod 777 /etc/rancher/k3s/k3s.yaml
        k3s kubectl get node
        """
        run_concurrent_command(namespace=namespace, instance_list=instance_list, command=command)

    management_instances = [i.ssh_host_port for i in instances['management']]
    all_instances = [i.ssh_host_port for i in instances['all_instances']]
    storage_instances = [i.ssh_host_port for i in instances['storage']]
    storage_instances_private = [i.private_ip_address for i in instances['storage']]
    management_instances_private = [i.private_ip_address for i in instances['management']]
    kubernetes_instances = [i.ssh_host_port for i in instances['kubernetes']]

    install_deps(instance_list=all_instances)
    sbcli_storage_node_deploy(instance_list=storage_instances, namespace=namespace)
    cluster_create_output = sbcli_cluster_create(instance_list_public=management_instances, instance_list_private=management_instances_private, namespace=namespace)
    sbcli_storage_node_add_node(cluster_create_output=cluster_create_output, storage_instances_private=storage_instances_private, namespace=namespace)
    k8s_cluster_create(instance_list=kubernetes_instances, namespace=namespace)

    return cluster_create_output
    
