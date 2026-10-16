# Mikrotik Configuration Backup

Ansible playbook to backup configurations from Mikrotik switches.

## Inventory

The following devices are managed:

| Name | IP Address |
|------|------------|
| mikrotik-sw-1 | 192.168.3.1 |
| mikrotik-sw-2 | 192.168.3.2 |

## Prerequisites

Install the required Ansible collections:

```bash
ansible-galaxy collection install community.routeros ansible.netcommon
```

## Usage

Run the backup playbook:

```bash
ansible-playbook -i inventory.yml backup_config.yml
```

To backup a specific device:

```bash
ansible-playbook -i inventory.yml backup_config.yml --limit mikrotik-sw-1
```

## Output

Configurations are saved to the `configs/` directory with timestamps:

- `<hostname>_full_<timestamp>.rsc` - Complete configuration export
- `<hostname>_compact_<timestamp>.rsc` - Compact export (without defaults)
- `<hostname>_latest.rsc` - Latest compact configuration (overwritten each run)

## SSH Configuration

The playbook uses SSH key authentication with the `admin` user. Ensure your private key (`~/.ssh/id_rsa`) is configured for access to the Mikrotik devices.

If using a different key, update `ansible_ssh_private_key_file` in `inventory.yml`.

## Provisioning

| Playbook | Hosts (`switch_role`) | Purpose |
|----------|----------------------|---------|
| `provision-vcf.yml` | `vcf` — mikrotik-sw-1 | VCF switch: bridge, VLANs + SVIs, DHCP, BGP to the UniFi, VLAN 15 transit |
| `provision-sw-2.yml` | `l2_aggregation` — mikrotik-sw-2 | L2 aggregation switch: bridge VLAN table, management SVI, hardening, SNMP |
| `update_interface_comments.yml` | all | Port comments from LLDP neighbours (+ static overrides) |

Both provisioning playbooks target `mikrotik_switches` and skip any host whose
`switch_role` (set in `host_vars/<host>/`) doesn't match, so running one
without `--limit` can't reconfigure the other switch.

Service hardening is shared by both playbooks (`tasks/hardening.yml`):
telnet/ftp/http/plaintext API off, SSH/Winbox/HTTPS/API-SSL only from
`services_allowed_from` (management, Semaphore/Home Assistant and house LAN
subnets), MAC-Winbox/telnet only on `mgmt_mac_interfaces`, bandwidth-test
off, SSH strong crypto, ed25519 host keys. Extra local accounts (e.g. Home
Assistant's read-only `ha-monitor`) are declared per host and applied by
`tasks/users.yml`; passwords are only set when creating a missing user.

Secrets live in `host_vars/<host>/secrets.yml` (gitignored — see the
`secrets.yml.example` next to it). sw-2's SNMP community is one of them; the
SNMP task is skipped if it isn't set.
