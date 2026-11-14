# NVIDIA vGPU Ansible Playbooks

This directory contains Ansible playbooks for installing and configuring the NVIDIA vGPU host driver on ESXi hosts, and the vGPU guest driver, licensing and container toolkit on Ubuntu guest VMs.

## Overview

Five playbooks work together to set up and validate NVIDIA vGPU capabilities:

1. **install_nvidia_esxi_host_driver.yml** - Installs the NVIDIA vGPU host driver (VIB) on ESXi hosts
2. **install_nvidia_drivers.yml** - Installs NVIDIA vGPU drivers and licensing (guest VMs)
3. **install_nvidia_containertoolkit.yml** - Installs NVIDIA Container Toolkit for Docker GPU support
4. **test_nvidia_container.yml** - Tests GPU access in Docker containers
5. **validate_nvidia_vGPU.yml** - Validates vGPU licensing and driver status

## Prerequisites

- ESXi hosts with an NVIDIA vGPU-capable GPU (see Playbook 0 for the host-side prerequisites)
- Ubuntu guest VMs with a vGPU profile assigned
- Ansible control node with SSH access to target hosts
- NFS share accessible at `nas.jameskilby.cloud:/mnt/pool1/ISO/nvidia` containing:
  - NVIDIA vGPU guest driver file: `NVIDIA-Linux-x86_64-595.71.05-grid.run`
  - License token file: `client_configuration_token_09-14-2026-15-15-53.tok`
- Docker installed on target hosts (for container toolkit playbook)

The host VIB and the guest driver must come from the same vGPU release. The current pairing is host `595.71.03` with guest `595.71.05` (same 595.71 branch); a mismatched branch is the most common reason a guest fails to bring the vGPU up.

The inventory has two groups: `esxi_hosts` (Playbook 0) and `vgpu_hosts` (Playbooks 1-4). Playbooks 1-4 target `hosts: all`, so pass `--limit vgpu_hosts` (or a host name) when running them against this inventory.

## Playbook 0: install_nvidia_esxi_host_driver.yml

### Purpose

Installs the NVIDIA vGPU host driver (VIB bundle) directly on ESXi hosts from an NFS datastore already mounted on the host. This is the host-side component that must be in place before guest VMs can be assigned vGPU profiles.

### Prerequisites

- SSH enabled on the ESXi host (`TSM-SSH` service) and root SSH access
- Your public key added to the host (ESXi does not use `~/.ssh/authorized_keys`):
  ```bash
  ssh root@<esxi-host> 'cat >> /etc/ssh/keys-root/authorized_keys' < ~/.ssh/id_ed25519.pub
  ```
  Alternatively run the playbook with `--ask-pass` (requires `sshpass`)
- The driver bundle zip present on an NFS datastore mounted on the host (default: `/vmfs/volumes/ISO/nvidia/`)
- No running VMs on the host — it must enter maintenance mode and will reboot

### What It Does

1. Checks whether the target driver version is already installed (idempotent)
2. Verifies the driver bundle exists on the datastore
3. Aborts if any VMs are still running on the host
4. Enters maintenance mode
5. Installs the VIB (`esxcli software vib install -d ...`), or updates it if an older NVIDIA VIB is present
6. Reboots the host if the install reports a reboot is required, and waits for it to return
7. Exits maintenance mode (only if the playbook put the host into it)
8. Verifies the VIB is present and the GPU is visible via `nvidia-smi` on the host

Hosts are processed one at a time (`serial: 1`) so a cluster is never fully drained.

### Variables

Override via inventory or `--extra-vars`:

```yaml
nvidia_esxi_driver_bundle: NVD-VGPU-800_595.71.03-1OEM.800.1.0.20613240.zip
nvidia_esxi_datastore: ISO            # datastore name under /vmfs/volumes/
nvidia_esxi_datastore_dir: nvidia/NVIDIA-GRID-vSphere-8-3/Host_Drivers  # subdirectory on the datastore ('' for none)
nvidia_esxi_driver_version: ""        # defaults to version parsed from the bundle filename
nvidia_esxi_maintenance_timeout: 300
nvidia_esxi_reboot_timeout: 1800
```

The defaults install `NVD-VGPU-800_595.71.03` from `/vmfs/volumes/ISO/nvidia/NVIDIA-GRID-vSphere-8-3/Host_Drivers/`. When a new driver version lands on the datastore, override `nvidia_esxi_driver_bundle` (and `nvidia_esxi_datastore_dir` if the folder changes) or update the defaults in the playbook.

### Usage

```bash
ansible-playbook -i inventory install_nvidia_esxi_host_driver.yml

# Single host
ansible-playbook -i inventory install_nvidia_esxi_host_driver.yml \
  --limit uk-bhr-p-esx-a.jameskilby.cloud

# Different driver bundle
ansible-playbook -i inventory install_nvidia_esxi_host_driver.yml \
  --extra-vars "nvidia_esxi_driver_bundle=<bundle>.zip"
```

If installation fails, the host is deliberately left in maintenance mode for safe inspection.

## Playbook 1: install_nvidia_drivers.yml

### Purpose

Installs NVIDIA vGPU drivers, configures licensing, and validates the installation.

### What It Does

1. Installs build tools, DKMS and kernel headers for the running kernel
2. Mounts the NFS share containing the driver installer and licence token
3. Compares the loaded driver version (`modinfo -F version nvidia`) with the version in the installer filename, and skips the install if they match (idempotent)
4. For an upgrade: stops `nvidia-gridd` and `nvidia-persistenced`, kills processes holding the GPU and unloads the NVIDIA kernel modules, rebooting first if they won't unload
5. Runs the installer with `--silent --no-cc-version-check --dkms`
6. For an upgrade: reboots, then rebuilds the DKMS module if the reboot picked up a newer kernel than the one the driver was built against
7. Verifies the loaded driver matches the target version
8. Deploys the licence token to `/etc/nvidia/ClientConfigToken/`, restarts and enables `nvidia-gridd`
9. Fails if `nvidia-smi -q` still reports the GPU as Unlicensed

### Variables

You can override these in your inventory or via `--extra-vars`:

```yaml
nvidia_vgpu_driver_file: NVIDIA-Linux-x86_64-595.71.05-grid.run
nvidia_vgpu_licence_file: client_configuration_token_09-14-2026-15-15-53.tok
nvidia_vgpu_driver_path: /tmp/<driver file>   # where the installer is copied on the guest
nvidia_nfs_server: nas.jameskilby.cloud
nvidia_nfs_export_path: /mnt/pool1/ISO/nvidia
nvidia_nfs_mount_point: /mnt/iso/nvidia
```

### Usage

```bash
# Run against all guest VMs
ansible-playbook -i inventory install_nvidia_drivers.yml --limit vgpu_hosts

# Run against specific host
ansible-playbook -i inventory install_nvidia_drivers.yml --limit hostname

# Override variables
ansible-playbook -i inventory install_nvidia_drivers.yml --limit vgpu_hosts \
  --extra-vars "nvidia_vgpu_driver_file=NVIDIA-Linux-x86_64-xxx-grid.run"
```

### Post-Installation

After successful installation, `nvidia-smi` should show licensed vGPU(s). The playbook will fail if the license check shows "Unlicensed".

## Playbook 2: install_nvidia_containertoolkit.yml

### Purpose

Installs the NVIDIA Container Toolkit to enable GPU access for Docker containers.

### What It Does

1. Installs required packages (curl, gpg, ca-certificates)
2. Adds NVIDIA Container Toolkit repository with proper GPG signing
3. Installs `nvidia-container-toolkit` package
4. Configures Docker to use the NVIDIA runtime
5. Restarts Docker service to apply configuration
6. Starts the `nvidia-gridd` licensing daemon
7. Validates GPU access by running `nvidia-smi` inside a test container

### Usage

```bash
# Run against all hosts
ansible-playbook -i inventory install_nvidia_containertoolkit.yml

# Run against specific host
ansible-playbook -i inventory install_nvidia_containertoolkit.yml --limit hostname
```

### Validation

The playbook runs a test container to verify GPU access:

```bash
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

If successful, you'll see the nvidia-smi output showing available GPUs.

## Playbook 3: test_nvidia_container.yml

### Purpose

Tests NVIDIA Container Toolkit functionality by running nvidia-smi inside a Docker container.

### What It Does

1. Runs `docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi`
2. Captures and displays the output
3. Fails if the command returns a non-zero exit code

### Usage

```bash
ansible-playbook -i inventory test_nvidia_container.yml
```

## Playbook 4: validate_nvidia_vGPU.yml

### Purpose

Validates that NVIDIA vGPU drivers are properly installed, licensed, and functional.

### What It Does

1. Checks that `nvidia-smi` is installed
2. Checks that `/etc/nvidia/ClientConfigToken/` exists and contains a `.tok` licence token
3. Confirms the `nvidia-gridd` service is registered and active
4. Checks licence status via `nvidia-smi -q`
5. Fails if the vGPU is unlicensed

### Usage

```bash
ansible-playbook -i inventory validate_nvidia_vGPU.yml
```

## Running All Playbooks

For a complete setup and validation, run all playbooks in order. The host driver goes first: the guest VM needs its vGPU profile (and so the host VIB) before the guest driver can find a GPU.

```bash
# 0. Install the host driver on the ESXi hosts (enters maintenance mode, may reboot)
ansible-playbook -i inventory install_nvidia_esxi_host_driver.yml

# 1. Install the guest driver and licensing
ansible-playbook -i inventory install_nvidia_drivers.yml --limit vgpu_hosts

# 2. Install container toolkit
ansible-playbook -i inventory install_nvidia_containertoolkit.yml --limit vgpu_hosts

# 3. Test container GPU access
ansible-playbook -i inventory test_nvidia_container.yml --limit vgpu_hosts

# 4. Validate licensing
ansible-playbook -i inventory validate_nvidia_vGPU.yml --limit vgpu_hosts
```

## GitHub Actions

`.github/workflows/deploy-vgpu.yml` (**Deploy vGPU**) runs these playbooks on the self-hosted runner via `workflow_dispatch`. Inputs:

| Input | Values |
|---|---|
| `playbook` | `validate`, `drivers`, `container-toolkit`, `test-container`, `full-chain` (guest playbooks 1-4), `host-driver` (Playbook 0) |
| `limit` | Host or group. Blank defaults to `esxi_hosts` for `host-driver` and `vgpu_hosts` for everything else |
| `inventory` | Defaults to `ansible/vGPU/inventory` |
| `check_mode` | Dry run with `--check --diff` |
| `verbosity`, `extra_vars` | Passed through to `ansible-playbook` |

`host-driver` is deliberately not part of `full-chain`: it drains and reboots ESXi hosts, so it only runs when chosen explicitly. The runner needs SSH key access to the ESXi hosts (see Playbook 0 prerequisites).

## Using Docker with GPU

After installation, you can run containers with GPU access:

```bash
# Run with all GPUs
docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.0-base nvidia-smi

# Run with specific GPU
docker run --rm --runtime=nvidia --gpus device=0 nvidia/cuda:12.0-base nvidia-smi

# Docker Compose example
services:
  gpu-app:
    image: nvidia/cuda:12.0-base
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
```

## Troubleshooting

### Driver Installation Issues

Check if drivers loaded:
```bash
lsmod | grep nvidia
```

View driver installation logs:
```bash
cat /var/log/nvidia-installer.log
```

### License Issues

Check nvidia-gridd service:
```bash
systemctl status nvidia-gridd
journalctl -u nvidia-gridd -f
```

View license status:
```bash
nvidia-smi -q | grep -i license
```

### Container Toolkit Issues

Verify Docker configuration:
```bash
cat /etc/docker/daemon.json
```

Test GPU access:
```bash
docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.0-base nvidia-smi
```

Check Docker daemon logs:
```bash
journalctl -u docker -f
```

## Notes

- Both driver playbooks are idempotent - they compare the installed version with the target and skip if they match
- The guest playbooks require root/sudo access (`become: yes/true`); the host driver playbook runs as root over SSH
- NFS mount uses optimized settings for large file transfers
- The guest driver installer runs with `--silent --no-cc-version-check --dkms` flags
- A 30-second pause is included after starting nvidia-gridd to allow license activation

## Files Created/Modified

### Driver Playbook
- `/etc/nvidia/ClientConfigToken/` - License token directory
- `/usr/bin/nvidia-smi` - NVIDIA management tool
- `/etc/systemd/system/nvidia-gridd.service` - Licensing daemon

### Container Toolkit Playbook
- `/etc/docker/daemon.json` - Docker runtime configuration
- `/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg` - Repository GPG key
- `/etc/apt/sources.list.d/nvidia-container-toolkit.list` - APT repository
