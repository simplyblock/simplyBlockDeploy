import fabric
import json
import os

from simplyBlockDeploy.ssh_keys import get_ssh_key_filename


def extract_host_port(machine):
    if ':' in machine:
        host, port = machine.split(':', 1)
    else:
        host = machine
        port = 22
    return host, port


def run_concurrent_command(namespace=None, instance_list=None, command=None):
    key_filename = get_ssh_key_filename(namespace)
    print("#######################################")
    print("Running command on {}".format(instance_list))
    print(command)
    print("with key file {}".format(key_filename))
    print("#######################################")
    if os.path.isfile(key_filename):
        connect_kwargs = {
            "key_filename": key_filename
        }
        connection_list = []
        for machine in instance_list:
            host, port = extract_host_port(machine)
            connection_list.append(fabric.Connection(host, user="rocky", connect_kwargs=connect_kwargs, port=port))
        group = fabric.ThreadingGroup.from_connections(connection_list)
        result = group.run(command)
        return result
    else:
        print("Error: Keyfile does not exist.")
        exit(1)


def run_command_return_output(namespace=None, machine=None, command=None):
    key_filename = "keys/{}".format(namespace)
    print("#######################################")
    print("Running command on {}".format(machine))
    print(command)
    print("with key file {}".format(key_filename))
    print("#######################################")
    connect_kwargs = {
        "key_filename": key_filename
    }
    host, port = extract_host_port(machine)
    connection = fabric.Connection(host, user="rocky", connect_kwargs=connect_kwargs, port=port)
    result = connection.run(command)
    print(result)
    return result.stdout.strip()