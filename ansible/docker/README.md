# Docker Installation with Ansible

Automated installation of Docker Engine on Ubuntu/Debian systems using official Docker repositories.

## Overview

This playbook installs Docker CE (Community Edition) with all necessary components including Docker Compose and Buildx plugins. It handles system prerequisites, repository configuration, and automatic reboots when required.

## Features

- ✅ Installs Docker CE from official Docker repository
- ✅ Configures GPG keys and APT sources securely
- ✅ Includes Docker Compose plugin (v2)
- ✅ Includes Docker Buildx plugin for multi-platform builds
- ✅ Handles automatic system reboots if required
- ✅ Enables and starts Docker service automatically
- ✅ Idempotent - safe to run multiple times

## Prerequisites

### Control Machine (Local)
- Ansible 2.9+
- SSH access to target host(s)

### Target Host
- Ubuntu/Debian operating system
- SSH access with sudo privileges
- Internet access for downloading packages
- Minimum 2GB disk space

## Quick Start

### 1. Create Inventory File

Create `inventory.ini`:

```ini
[docker_hosts]
server1.example.com ansible_user=your_username
server2.example.com ansible_user=your_username
```

### 2. Run the Playbook

```bash
ansible-playbook -i inventory.ini install_docker.yml
```

### 3. Verify Installation

```bash
ansible docker_hosts -i inventory.ini -m shell -a "docker --version"
ansible docker_hosts -i inventory.ini -m shell -a "docker compose version"
```

## What the Playbook Does

1. **Installs Prerequisites**: Required system packages (curl, gnupg, ca-certificates, etc.)
2. **Checks for Reboot**: Detects if a reboot is required from previous updates
3. **Handles Reboots**: Automatically reboots system if needed and waits for reconnection
4. **Configures GPG Keys**: Downloads and installs Docker's official GPG key
5. **Adds Repository**: Configures Docker's official APT repository
6. **Installs Docker**: Installs Docker CE, CLI, containerd, and plugins
7. **Enables Service**: Ensures Docker service starts automatically on boot
8. **Configures the daemon**: Merges `docker_daemon_options` into `/etc/docker/daemon.json` (capped logs, live-restore) and restarts Docker if it changed — see [Daemon configuration](#daemon-configuration)

## Playbook Details

### Installed Components

| Component | Description |
|-----------|-------------|
| `docker-ce` | Docker Community Edition engine |
| `docker-ce-cli` | Docker command-line interface |
| `containerd.io` | Container runtime |
| `docker-buildx-plugin` | Multi-platform build support |
| `docker-compose-plugin` | Docker Compose v2 |

### Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `docker_gpg_path` | `/etc/apt/keyrings/docker.gpg` | Path to Docker GPG key |
| `docker_repo` | Docker official repository | APT repository configuration |
| `allow_reboot` | `false` | Reboot automatically when `/var/run/reboot-required` exists |
| `docker_daemon_options` | log caps + live-restore | Keys merged into `/etc/docker/daemon.json` (see below) |
| `docker_host_sysctls` | `vm.swappiness: 10`, `fs.inotify.max_user_instances: 1024` | Written to `/etc/sysctl.d/90-homelab-docker.conf` |
| `docker_journald_max_use` | `1G` | journald `SystemMaxUse`, via `/etc/systemd/journald.conf.d/90-size.conf` |

### Daemon configuration

The playbook merges `docker_daemon_options` into `/etc/docker/daemon.json`. Keys already in the file are kept, so the `nvidia` runtime written by `../vGPU/install_nvidia_containertoolkit.yml` survives. Keys in `docker_daemon_options` override existing ones. The file is checked with `dockerd --validate` before it is written.

```json
{
    "live-restore": true,
    "log-driver": "json-file",
    "log-opts": { "max-file": "3", "max-size": "10m" }
}
```

- **Log caps** apply to every container, including ones started outside compose (`docker run`, Portainer agent, DockFlare's cloudflared). They only apply to containers created **after** the change. Existing ones keep their old log config until recreated. Compose files that set their own `logging:` block still win.
- **live-restore** keeps containers running while `dockerd` restarts or is upgraded. Turning it on needs one Docker restart, and that first restart **does** restart every container. Containers with a restart policy come back on their own.

### Host tuning

Tagged `host-tuning`. It writes the kernel settings in `docker_host_sysctls` and caps the journal at `docker_journald_max_use`. It applies them straight away with `sysctl -p` and a journald restart, which doesn't affect containers.

- **`vm.swappiness` 10**: on a host with plenty of RAM, idle container memory stays in RAM instead of being swapped out to grow the page cache.
- **`fs.inotify.max_user_instances` 1024**: many containers watch folders (media servers, *arr apps, document ingest), and the default of 128 runs out.

```bash
ansible-playbook -i inventory install_docker.yml --tags host-tuning
```

Apply only the daemon settings to an existing host (no package changes):

```bash
ansible-playbook -i inventory install_docker.yml --tags daemon --check --diff   # preview
ansible-playbook -i inventory install_docker.yml --tags daemon
```

### Reboot Behavior

The playbook checks for `/var/run/reboot-required` and automatically reboots if needed:
- **Pre-reboot delay**: 60 seconds
- **Reboot timeout**: 600 seconds (10 minutes)
- **Post-reboot delay**: 60 seconds

## Post-Installation

### Add User to Docker Group

To run Docker commands without sudo:

```bash
# On the target host
sudo usermod -aG docker $USER

# Log out and back in for changes to take effect
```

### Verify Docker Installation

```bash
# Check Docker version
docker --version

# Check Docker Compose version
docker compose version

# Test Docker with hello-world
docker run hello-world

# Check Docker service status
sudo systemctl status docker
```

### Test Docker Functionality

```bash
# Run a simple container
docker run --rm nginx:alpine echo "Docker is working!"

# Build a test image with Buildx
docker buildx version
```

## Advanced Usage

### Custom Variables

Override default variables:

```bash
ansible-playbook -i inventory.ini install_docker.yml \
  -e "docker_gpg_path=/custom/path/docker.gpg"
```

### Limit to Specific Hosts

```bash
ansible-playbook -i inventory.ini install_docker.yml --limit server1.example.com
```

### Check Mode (Dry Run)

Preview changes without executing:

```bash
ansible-playbook -i inventory.ini install_docker.yml --check
```

### Verbose Output

```bash
ansible-playbook -i inventory.ini install_docker.yml -v
# or for more detail
ansible-playbook -i inventory.ini install_docker.yml -vvv
```

## Troubleshooting

### GPG Key Issues

```
GPG error: ... NO_PUBKEY
```

**Solution**: The playbook downloads and installs the GPG key automatically. If issues persist, manually verify:

```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

### Repository Not Found

```
Failed to fetch ... 404 Not Found
```

**Solution**: Verify your Ubuntu/Debian version is supported by Docker. Check [Docker's official documentation](https://docs.docker.com/engine/install/ubuntu/).

### Permission Denied (Docker Socket)

```
permission denied while trying to connect to the Docker daemon socket
```

**Solution**: Add user to docker group and re-login:

```bash
sudo usermod -aG docker $USER
# Log out and back in
```

### Service Won't Start

```
Failed to start docker.service
```

**Solution**: Check logs for errors:

```bash
sudo journalctl -u docker.service -n 50
```

Common causes:
- Conflicting existing installations
- Insufficient system resources
- Kernel module issues

## Security Considerations

- **Docker Socket**: Be cautious about granting Docker socket access (equivalent to root access)
- **User Groups**: Only add trusted users to the `docker` group
- **Updates**: Regularly update Docker to patch security vulnerabilities
- **Image Sources**: Only use trusted Docker images from verified sources

## Integration with Other Playbooks

This playbook is a prerequisite for:
- **Portainer Agent** (`../portainer/install_portainer_agent.yml`)
- **Traefik Deployment** (`../traefik/traefik_deploy.yml`)
- **NVIDIA Container Toolkit** (`../vGPU/install_nvidia_containertoolkit.yml`)
- **VCF Offline Bundle Server** (`../VCF/install_offline_bundle_server.yml`)

## Maintenance

### Update Docker

Docker is installed with `state: latest`, so re-running the playbook will update to the latest version:

```bash
ansible-playbook -i inventory.ini install_docker.yml
```

### Uninstall Docker

To manually remove Docker (not included in playbook):

```bash
sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
```

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Docker Hub](https://hub.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Docker Buildx Documentation](https://docs.docker.com/buildx/)
- [Main Project README](../README.md)

## Contributing

When modifying this playbook:

1. Test on a clean Ubuntu/Debian system
2. Verify all components install correctly
3. Check that Docker service starts properly
4. Update this README with any new features or changes
5. Follow Ansible best practices for idempotency

## Support

For issues related to:
- **Docker Installation**: Check [Docker's official documentation](https://docs.docker.com/engine/install/)
- **Ansible Playbooks**: See the [main project README](../README.md)
- **System Requirements**: Verify your OS is supported by Docker
