# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **local monorepo** that combines multiple upstream repositories to allow working on changes that span multiple components simultaneously. Each component has its own upstream repository; changes made here are upstreamed to the respective repos separately. The monorepo itself is not the canonical source.

The components are:

- **`sbcli/`** — Python control plane core, web API, and `sbctl` CLI
- **`operator/`** — Kubernetes operator (Go/kubebuilder)
- **`helm-charts/`** — Helm charts for deployment

Together they form the **Simplyblock Control Plane** — a Kubernetes-native, distributed NVMe-over-Fabrics block storage system.

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

## Architecture

### Data Flow

```
sbctl CLI  →  Web API (FastAPI v2 / Flask v1)  →  Core Logic  →  FoundationDB
                                                        ↕
                                                  Storage Nodes (via RPC/gRPC)
                                                        ↕
                                               Kubernetes Operator (Go)
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
