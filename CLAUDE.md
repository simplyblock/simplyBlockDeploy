# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **local monorepo** that combines multiple upstream repositories to allow working on changes that span multiple components simultaneously. Each component has its own upstream repository; changes made here are upstreamed to the respective repos separately. The monorepo itself is not the canonical source.

The components are:

- **`sbcli/`** — Python control plane core, web API, and `sbctl` CLI
- **`operator/`** — Kubernetes operator (Go/kubebuilder)
- **`helm-charts/`** — Helm charts for deployment
- **`csi/`** — Kubernetes CSI driver (Go) for NVMe-over-TCP storage provisioning

Together they form the **Simplyblock Control Plane** — a Kubernetes-native, distributed NVMe-over-Fabrics block storage system.

## Syncing Upstream Changes

To pull the latest `main` from all four upstream repos into this monorepo, run from the repo root while on the `main` branch with a clean working tree:

```bash
./update-upstreams.sh
```

Each component is tracked as a `git subtree --squash`. The script runs `git subtree pull` for each and fails fast if any component has a merge conflict, leaving the repo in a state where you can resolve conflicts and complete the merge manually.

## Commands

### sbcli (Python)

```bash
# Install dependencies
pip install -r sbcli/requirements.txt

# Run all tests
cd sbcli && pytest

# Run a specific test file
cd sbcli && pytest tests/test_backup.py

# Run tests in a specific directory
cd sbcli && pytest simplyblock_core/test

# Performance tests are excluded from the default run; run explicitly:
cd sbcli && pytest tests/perf/

# Lint
cd sbcli && ruff check .

# Type checking
cd sbcli && mypy --config-file pyproject.toml

# Local dev environment (requires Docker)
sudo docker compose -f sbcli/docker-compose-dev.yml up --build -d

# Regenerate CLI code after modifying cli-reference.yaml
./sbcli/simplyblock_cli/scripts/generate.sh
```

### operator (Go)

```bash
cd operator

make build          # Build manager binary
make test           # Run unit tests
make test-e2e       # Run e2e tests using Kind
make lint           # Run golangci-lint
make lint-fix       # Run golangci-lint with auto-fix
make fmt            # Format code (go fmt)
make vet            # Run go vet
make manifests      # Regenerate CRDs and RBAC from types
make generate       # Regenerate DeepCopy methods
make run            # Run operator locally against current kubeconfig
```

### helm-charts

```bash
helm lint charts/simplyblock-operator
helm dependency update charts/simplyblock-operator

# Sync CRDs/RBAC from operator repo (run after CRD changes)
helm-charts/scripts/sync-from-manager.sh
```

### csi (Go)

```bash
cd csi

make spdkcsi       # Build the CSI driver binary to _out/
make image         # Build multi-arch Docker image (amd64 + arm64)
make test          # Run go mod verify + unit tests
make unit-test     # Run unit tests only (with race detector and coverage)
make e2e-test      # Run e2e tests (requires a running cluster; uses Ginkgo)
make sanity-test   # Run CSI spec compliance tests
make lint          # Run golangci-lint
make clean         # Remove build artifacts and test cache
```

Key build variables: `CSI_IMAGE_REGISTRY` (default: `simplyblock`), `CSI_IMAGE_TAG` (default: `latest`), `GOARCH`.

## Architecture

### Data Flow

```
sbctl CLI  →  Web API (FastAPI v2 / Flask v1)  →  Core Logic  →  FoundationDB
                                                        ↕
                                                  Storage Nodes (via RPC/gRPC)
                                                        ↕
                                               Kubernetes Operator (Go)
                                                        ↕
                                          CSI Driver (Controller + Node pods)
                                                        ↕
                                             Kubernetes PersistentVolumes
```

### sbcli Component Structure

- **`simplyblock_web/`** — Dual API layer: Flask v1 (`api/v1/`) and FastAPI v2 (`api/v2/`). The FastAPI app is the main entry point (`app.py`).
- **`simplyblock_core/`** — All business logic:
  - `cluster_ops.py` — Cluster lifecycle management
  - `storage_node_ops.py` — Storage node management (very large file, ~310KB)
  - `db_controller.py` — FoundationDB access layer
  - `rpc_client.py` — RPC client for communicating with storage nodes
  - `models/` — Data model definitions (cluster, pool, device, etc.)
  - `controllers/` — Feature controllers (backup, tasks, QoS, snapshots)
  - `services/` — Service layer abstractions
  - `kms/` — HashiCorp Vault KMS integration
- **`simplyblock_cli/`** — `sbctl` CLI. Commands are **auto-generated** from `simplyblock_cli/sbctl/cli-reference.yaml` into `simplyblock_cli/cli.py`. Do not edit `cli.py` directly; edit the YAML and run `generate.sh`. CLI function implementations live in `clibase.py`, named `<command>__<subcommand>` (hyphens become underscores).

### Operator Component Structure

The operator manages 8 CRDs defined in `api/v1alpha1/`:
- `StorageCluster`, `StorageNode`, `Pool`, `Task`, `SnapshotReplication`, `StorageBackup`, `StorageRestore`, `ControlPlane`

Controllers in `internal/controller/` reconcile these resources. The operator communicates with the control plane via `internal/webapi/`.

### CSI Component Structure

The CSI driver (`csi.simplyblock.io`) runs as two distinct Kubernetes workloads:

- **Controller** (StatefulSet) — handles volume lifecycle via the CSI Controller API: create/delete volumes, snapshots, clones, and expansion. Runs with sidecar containers (external-provisioner, snapshotter, attacher, resizer).
- **Node** (DaemonSet, one pod per node) — handles attach/mount via the CSI Node API: stages NVMe-TCP connections and publishes volumes into pods.

Key packages under `pkg/`:

- **`spdk/`** — Simplyblock-specific CSI implementation:
  - `controllerserver.go` — volume/snapshot lifecycle (CreateVolume, DeleteVolume, CreateSnapshot, ControllerExpandVolume, etc.)
  - `nodeserver.go` — per-node NVMe attach/mount (NodeStageVolume, NodePublishVolume, topology discovery)
  - `identityserver.go` — CSI plugin identity/capabilities
  - `driver.go` — driver initialisation and capability registration
- **`util/`** — shared utilities:
  - `jsonrpc.go` — JSON-RPC client for communicating with the sbcli control plane API
  - `initiator.go` — NVMe-TCP initiator (connecting/managing NVMe devices on the host)
  - `nvmf.go` — NVMe-over-Fabrics discovery
  - `guardian.go` — volume protection and cleanup logic
  - `idlocker.go` — per-volume locking to serialise concurrent operations
- **`csi-common/`** — base gRPC server and default CSI handler stubs

Deployment manifests live in `deploy/kubernetes/`; the Helm chart is in `charts/spdk-csi/`. The driver communicates with the sbcli control plane via JSON-RPC (Bearer token auth for v2 endpoints). Multi-cluster topology (zone/region → storage cluster mapping) is configured via a ConfigMap; see `docs/multi-cluster-support.md`.

### Local Development

FoundationDB is required for the Python control plane. The `docker-compose-dev.yml` spins up FDB and the control plane together. For running tests that touch FDB locally (outside Docker), you need the `libfdb_c` client library installed matching version 7.3.x.

## Error Handling (Python — required by CONTRIBUTING.md)

All Python code must use **exception-based error handling**. When modifying existing code that uses other patterns (return codes, boolean flags, `None` returns on error), convert the touched sections.

- Raise specific exceptions: use `TypeError`/`ValueError` for generic failures; define custom types (e.g., `APIError`, `StorageNodeError`) for domain-specific errors
- Document expected exceptions in docstrings with `Raises:` sections
- Do not catch bare `Exception` without logging and re-raising
- Do not return `None` or sentinel values to signal errors

## Key Configuration

- `sbcli/pyproject.toml` — ruff, mypy, and pytest configuration. `simplyblock_cli/cli.py` is excluded from ruff. `tests/perf/` is excluded from default pytest discovery.
- `operator/.golangci.yml` — golangci-lint rules for the operator
- `operator/PROJECT` — kubebuilder project manifest listing all CRD definitions
- `csi/scripts/golangci.yml` — golangci-lint rules for the CSI driver (the root-level `csi/.golangci.yml` is a stub that defers to this file)
