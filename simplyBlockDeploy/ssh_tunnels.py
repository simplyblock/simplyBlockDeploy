import time
from sshtunnel import SSHTunnelForwarder

from simplyBlockDeploy.ssh_keys import get_ssh_key_filename


def create_ssh_tunnel(namespace, local_ports, remote_hosts, ssh_host, remote_port=22):
    server = SSHTunnelForwarder(
        ssh_host=ssh_host,
        ssh_username="rocky",
        ssh_pkey=get_ssh_key_filename(namespace),
        remote_bind_addresses=[(host, remote_port) for host in remote_hosts],
        local_bind_addresses=[('localhost', port) for port in local_ports]
    )
    server.start()
    print(f"SSH tunnels established.")


def main():
    # Example usage
    remote_hosts = ['10.141.1.190']
    ssh_host = '18.201.254.94'
    local_ports = [8022]
    create_ssh_tunnel('test', local_ports, remote_hosts, ssh_host)
    time.sleep(3600)


if __name__ == "__main__":
    main()

