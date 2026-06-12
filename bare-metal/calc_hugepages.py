#!/usr/bin/env python3
"""
Calculate required hugepages for a simplyblock storage node.

Mirrors the exact formula from sbcli:
  calculate_unisolated_cores -> calculate_core_allocations ->
  calculate_pool_count -> calculate_minimum_hp_memory -> adjust_hugepages

Usage:
  python3 calc_hugepages.py --cpus 8 --ram-mb 15735 --nvme 4
  python3 calc_hugepages.py --cpus 8 --ram-mb 15735 --nvme 4 --core-percentage 65 --max-lvol 10
  python3 calc_hugepages.py --cpus 32 --ram-mb 65536 --nvme 8 --core-percentage 80 --max-lvol 256 --max-size-gb 20480
"""

import argparse
import math
import sys

# Constants from sbcli/simplyblock_core/constants.py
EXTRA_SMALL_POOL_COUNT = 30000
EXTRA_LARGE_POOL_COUNT = 10240
EXTRA_HUGE_PAGE_MEMORY = 3221225472  # 3 GiB


def calculate_unisolated_cores(total_cores, cores_percentage=0):
    if cores_percentage:
        return math.ceil(total_cores * (100 - cores_percentage) / 100)
    if total_cores <= 10:
        return 2
    if total_cores <= 20:
        return 3
    if total_cores <= 28:
        return 4
    return math.ceil(total_cores * 0.15)


def calculate_core_allocations(isolated_count, alceml_count):
    """
    Simplified (non-hyperthreading-aware) version of sbcli's
    calculate_core_allocations. Returns (poller_cores, distrib_cores).
    """
    remaining = isolated_count

    if isolated_count < 12:
        # app + jm + jc_singleton + 1 alceml + lvol_poller = 5 fixed
        reserved = min(5, remaining)
        remaining -= reserved
    elif isolated_count < 22:
        # app + jm + jc_singleton + 2 alceml + lvol_poller = 6 fixed
        reserved = min(6, remaining)
        remaining -= reserved
    else:
        # app + jm + jc_singleton + lvol_poller + alceml_count
        reserved = min(4 + alceml_count, remaining)
        remaining -= reserved

    dp = remaining // 2
    if dp >= 17:
        distrib = 24
        poller = remaining - 24
    elif dp >= 12:
        distrib = 12
        poller = remaining - 12
    else:
        distrib = dp
        poller = dp

    # leftover core goes to pollers
    leftover = remaining - distrib - poller
    poller += leftover

    return poller, distrib


def calculate_pool_count(alceml_count, number_of_distribs, cpu_count, poller_count):
    poller_number = poller_count if poller_count else cpu_count

    small_pool = (
        384 * (alceml_count + number_of_distribs + 3 + poller_count)
        + (6 + alceml_count + number_of_distribs) * poller_number * 127
        + 384 + 128 * poller_number
        + EXTRA_SMALL_POOL_COUNT
    )
    large_pool = (
        48 * (alceml_count + number_of_distribs + 3 + poller_count)
        + (6 + alceml_count + number_of_distribs) * 32
        + poller_number * 15 + 384 + 16 * poller_number
        + EXTRA_LARGE_POOL_COUNT
    )
    return int(small_pool), int(large_pool)


def calculate_minimum_hp_memory(small_pool, large_pool, max_lvol, max_prov, cpu_count):
    pool_kb = (small_pool * 8 + large_pool * 128) / 1024
    mem_bytes = (
        (4 * cpu_count + 1.1 * pool_kb + 22 * max_lvol) * (1024 * 1024)
        + EXTRA_HUGE_PAGE_MEMORY
    )
    return int(2.0 * mem_bytes)


def adjust_hugepages(pages):
    remainder = pages % 500
    pages = pages + (500 - remainder)
    decimal_val = float(str(pages)[0] + '.' + str(pages)[1])
    add_val = int(decimal_val * 24)
    return pages + add_val


def calc(total_cpus, total_ram_mb, nvme_devices, core_percentage, max_lvol, max_size_bytes, nodes_per_socket):
    # --- core allocation ---
    unisolated = calculate_unisolated_cores(total_cpus, core_percentage)
    isolated = total_cpus - unisolated
    isolated_per_node = isolated // nodes_per_socket

    poller_cores, distrib_cores = calculate_core_allocations(isolated_per_node, nvme_devices)

    cpu_count = isolated_per_node
    poller_count = poller_cores if poller_cores else cpu_count

    # number_of_distribs: default 2, becomes distrib_cores count if > 2
    number_of_distribs = max(2, distrib_cores)
    # passed to calculate_pool_count as 2 * number_of_distribs
    distribs_arg = 2 * number_of_distribs

    alceml_count = nvme_devices // nodes_per_socket

    # --- pool counts ---
    small_pool, large_pool = calculate_pool_count(alceml_count, distribs_arg, cpu_count, poller_count)

    # --- minimum hugepage memory ---
    min_hp = calculate_minimum_hp_memory(small_pool, large_pool, max_lvol, max_size_bytes, cpu_count)
    spdk_mem = max(min_hp, max_size_bytes)

    # --- K8s pod resource request (MEM_MEGA in kubernetes.py) ---
    spdk_mib = math.ceil(spdk_mem / (1024 * 1024))
    mem_mega = (spdk_mib // 2) * 2 + 512  # round to even MiB + 512 MiB buffer

    # --- kernel hugepage count (apply_config in kubernetes.py) ---
    # user_baseline=0 (fresh node, baseline file pre-seeded with 0)
    raw_pages = (spdk_mem + 1_000_000_000) // 2_000_000
    nr_hugepages = adjust_hugepages(raw_pages)

    hugepage_mem_mib = nr_hugepages * 2
    remaining_mib = total_ram_mb - hugepage_mem_mib

    return {
        "isolated_cores": isolated_per_node,
        "poller_cores": poller_cores,
        "distrib_cores": distrib_cores,
        "alceml_count": alceml_count,
        "number_of_distribs": number_of_distribs,
        "small_pool": small_pool,
        "large_pool": large_pool,
        "spdk_mem_gib": spdk_mem / 1024**3,
        "k8s_request_mib": mem_mega,
        "nr_hugepages": nr_hugepages,
        "hugepage_mem_mib": hugepage_mem_mib,
        "remaining_mib": remaining_mib,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Calculate required hugepages for a simplyblock storage node.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--cpus",             type=int, required=True, help="Total CPU cores on the node")
    parser.add_argument("--ram-mb",           type=int, required=True, help="Total RAM in MiB (grep MemTotal /proc/meminfo / 1024)")
    parser.add_argument("--nvme",             type=int, required=True, help="Number of NVMe devices on the node")
    parser.add_argument("--core-percentage",  type=int, default=100,   help="spec.corePercentage (default: 100)")
    parser.add_argument("--max-lvol",         type=int, default=256,   help="spec.maxLogicalVolumeCount (default: 256)")
    parser.add_argument("--max-size-gb",      type=int, default=0,     help="spec.maxSize in GiB (default: 0)")
    parser.add_argument("--nodes-per-socket", type=int, default=1,     choices=[1, 2], help="spec.nodesPerSocket (default: 1)")

    args = parser.parse_args()

    max_size_bytes = args.max_size_gb * 1024**3

    r = calc(
        total_cpus=args.cpus,
        total_ram_mb=args.ram_mb,
        nvme_devices=args.nvme,
        core_percentage=args.core_percentage,
        max_lvol=args.max_lvol,
        max_size_bytes=max_size_bytes,
        nodes_per_socket=args.nodes_per_socket,
    )

    print()
    print("=== Input ===")
    print(f"  CPUs:              {args.cpus}")
    print(f"  RAM:               {args.ram_mb} MiB ({args.ram_mb/1024:.1f} GiB)")
    print(f"  NVMe devices:      {args.nvme}")
    print(f"  corePercentage:    {args.core_percentage}%")
    print(f"  maxLogicalVolumeCount: {args.max_lvol}")
    print(f"  maxSize:           {args.max_size_gb} GiB")
    print(f"  nodesPerSocket:    {args.nodes_per_socket}")

    print()
    print("=== Core allocation ===")
    print(f"  Isolated cores:    {r['isolated_cores']}")
    print(f"  Poller cores:      {r['poller_cores']}")
    print(f"  Distrib cores:     {r['distrib_cores']}  ->  number_of_distribs={r['number_of_distribs']}")
    print(f"  NVMe per node:     {r['alceml_count']}")

    print()
    print("=== Pool counts ===")
    print(f"  small_pool:        {r['small_pool']:,}")
    print(f"  large_pool:        {r['large_pool']:,}")

    print()
    print("=== Memory ===")
    print(f"  SPDK memory:       {r['spdk_mem_gib']:.2f} GiB")
    print(f"  K8s pod request:   hugepages-2Mi: {r['k8s_request_mib']}Mi")
    print()
    print(f"  NR_HUGEPAGES       = {r['nr_hugepages']}  ({r['hugepage_mem_mib']} MiB = {r['hugepage_mem_mib']/1024:.1f} GiB)")
    print(f"  Remaining for OS   = {r['remaining_mib']} MiB ({r['remaining_mib']/1024:.1f} GiB)")
    print()

    if r['remaining_mib'] < 1024:
        print("  WARNING: less than 1 GiB remaining for OS and other pods.")
    elif r['remaining_mib'] < 2048:
        print("  NOTE: remaining memory is tight if management pods also run on this node.")
    else:
        print("  OK: sufficient memory remaining for OS and node-local pods.")
    print()


if __name__ == "__main__":
    main()
