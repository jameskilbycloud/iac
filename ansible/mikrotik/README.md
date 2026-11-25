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

The BGP tasks in `provision-vcf.yml` use the RouterOS API (`community.routeros.api`, API-SSL on port 8729), which needs `librouteros` in Ansible's own Python (see `requirements.txt`). With Homebrew's Ansible:

```bash
/opt/homebrew/Cellar/ansible/*/libexec/bin/python -m pip install -r requirements.txt
```

Without it, the first API task fails with *Failed to import the required Python library (librouteros)*.

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

The playbook uses SSH key authentication with the `admin` user and the key set in `inventory.yml` (`~/.ssh/id_ed25519`). The API tasks log in with `mikrotik_api_password` from `host_vars/<host>/secrets.yml`.

If using a different key, update `ansible_ssh_private_key_file` in `inventory.yml`.

## Provisioning

| Playbook | Hosts (`switch_role`) | Purpose |
|----------|----------------------|---------|
| `provision-vcf.yml` | `vcf` — mikrotik-sw-1 | VCF switch: bridge, VLANs + SVIs, DHCP, iBGP to the UniFi, eBGP to the NTNX1 NSX Edges, VLAN 15 transit |
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

## BGP on sw-1 (`provision-vcf.yml --tags bgp`)

sw-1 (AS 65000) has two kinds of BGP session. All of them are set in `host_vars/mikrotik-sw-1/vcf.yml`:

| Session | Peer | Sends | Accepts |
|---|---|---|---|
| iBGP `unifi` | UniFi Dream Machine Beast, 192.168.15.248 on the VLAN 15 transit | `bgp-vcf-out`: each of `bgp_advertise_networks` (exact match) and each of `bgp_advertise_blocks` with anything inside it (`dst in`), with sw-1 as next hop (`nexthop-choice=force-self`) | `bgp-in`: default route only |
| eBGP `ntnx1-edge-1{a,b}-10{6,7}` (tag `nsx_edge_bgp`) | NTNX1 NSX Edges, AS 65100: edge-1a .2 and edge-1b .3 on VLAN 106 and 107 (`nsx_edge_bgp_peers`) | `nsx-edge-out`: default route only (`default-originate`) | `nsx-edge-in`: `nsx_edge_accept_networks` and anything inside them |

On sw-1, `bgp_advertise_blocks` and `nsx_edge_accept_networks` are both 192.168.110.0/24, the NTNX1 VPC external IP block. So any NSX network in that block reaches the rest of the network: edges → sw-1 → UniFi. `nexthop-choice` is needed because routes sw-1 learns from the edges would otherwise reach the UniFi with an edge address as next hop, which the UniFi has no route to. In RouterOS 7.25 it's a top-level connection property; there's no `output.nexthop-choice`. The edge connections deliberately use no template, because `bgp-vcf` redistributes connected routes.

```bash
ansible-playbook -i inventory.yml provision-vcf.yml --limit mikrotik-sw-1 --tags bgp            # all BGP
ansible-playbook -i inventory.yml provision-vcf.yml --limit mikrotik-sw-1 --tags nsx_edge_bgp   # edge sessions only
```

Filter chains are rebuilt only when their rule count is wrong. Adding or removing an advertised network or block therefore rebuilds `bgp-vcf-out` once, which briefly withdraws the VCF routes from the UniFi. A change to the UniFi connection itself resets that session; graceful restart keeps the UniFi's routes in the meantime. `--check` runs only the reads, because the RouterOS command and API modules don't support check mode.

Check the result on the switch:

```
/routing bgp session print          # all five sessions should show E (established)
/routing filter rule print where chain~"bgp-vcf-out|nsx-edge"
/ip route print where dst-address in 192.168.110.0/24
```

