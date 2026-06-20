# Simplyblock Ansible
Ansible replacement for `bootstrap-cluster.sh` that installs sbcli, configures nodes, creates the cluster, adds storage/management nodes, and writes the cluster secret locally.

## Inventory
Example inventory:
```
[management_nodes]
192.168.10.111
192.168.10.115

[storage_nodes]
192.168.10.112 ssds="['0000:00:02.0', '0000:00:03.0', '0000:00:04.0', '0000:00:05.0']"
192.168.10.113 ssds="['0000:00:02.0', '0000:00:03.0', '0000:00:04.0', '0000:00:05.0']"
192.168.10.114 ssds="['0000:00:02.0', '0000:00:03.0', '0000:00:04.0', '0000:00:05.0']"
```
Defaults such as `management_nic`, `data_nic`, proxy settings, and storage wipe parameters live in `group_vars/all`.

## Running
```
ansible-playbook -i inventory/<file> \
  -e "pool=pool1 log_del_interval=60 metrics_retention_period=24h nr_hugepages=0 data_nics=eth1" \
  cluster.yml
```

## Key variables (covering bootstrap-cluster.sh flags)
- Install/command: `sbcli_package` (e.g. `sbcli-dev` or git URL), `sbcli_command_name`, `sb_image`, `ultra_image`, `debug=true`.
- Safety: `cleanup=true` (runs deploy-cleaner, docker prune; reboots storage nodes), `wipe_storage_devices=true` plus `storage_wipe_devices`/`storage_wipe_partitions` to mirror partition cleanup, `nr_hugepages=<count>`.
- Storage configure: `max_lvol`, `max_size`, `nodes_per_socket`, `sockets_to_use`, `pci_allowed`, `pci_blocked`.
- Cluster create: `log_del_interval`, `metrics_retention_period`, `contact_point`, `grafana_endpoint`, `data_chunks_per_stripe`, `parity_chunks_per_stripe`, `distr_chunk_bs`, `cap_warn`, `cap_crit`, `prov_cap_warn`, `prov_cap_crit`, `ha_type`, `enable_node_affinity`, `qpair_count`, `mode` (`docker`|`kubernetes`).
- Storage add: `max_snapshot`, `iobuf_small_bufsize`, `iobuf_large_bufsize`, `journal_partition`, `data_nics`, `spdk_image`, `id_device_by_nqn`, `disable_ha_jm`, `enable_test_device`, `full_page_unmap`, `spdk_debug`, `ha_jm_count`, `jm_percent`, `partition_size`.
- Behaviour toggles: `k8s_snode=true` skips storage deploy/add on bare metal; `pool` names the pool (defaults to `testing1`).

## SSH bootstrap
Use `ssh.yml` to accept host keys and deploy your SSH public key:
```
ansible-playbook -i inventory/<file> -k -e "public_key='<key>'" ssh.yml
```

## Testing
`test/` contains API smoke tests:
```
pytest --entrypoint=<IP> --cluster=<cluster_id> --secret=<secret>
```
