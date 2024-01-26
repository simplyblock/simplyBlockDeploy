import fabric
import json
import os

def run_concurrent_command(namespace=None, instance_list=None, command=None):
    key_filename = "keys/{}".format(namespace)
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
            connection_list.append(fabric.Connection(machine, user="rocky", connect_kwargs=connect_kwargs))
        group = fabric.ThreadingGroup.from_connections(connection_list)
        result = group.run(command)
        return result
    else:
        print("Error: Keyfile does not exist.")
        exit(1)

def run_command_return_output(namespace=None, host=None, command=None):
    key_filename = "keys/{}".format(namespace)
    print("#######################################")
    print("Running command on {}".format(host))
    print(command)
    print("with key file {}".format(key_filename))
    print("#######################################")
    connect_kwargs = {
        "key_filename": key_filename
    }
    connection = fabric.Connection(host, user="rocky", connect_kwargs=connect_kwargs)
    result = connection.run(command)
    print(result)
    return result.stdout.strip()