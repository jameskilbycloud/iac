# Auto-Documenting MikroTik Switch Ports with Ansible and LLDP Neighbours

One of the small but persistent annoyances of managing network switches is keeping port labels up to date. You cable something up, then six months later you're staring at a list of `qsfp28-1-2` entries wondering what's plugged into what. This post covers a short Ansible playbook I wrote to solve that problem on my MikroTik switches — it pulls LLDP neighbour data directly from the switch and writes it back as interface comments, giving you a self-updating port map with no manual labelling required.

---

## The Problem

MikroTik RouterOS supports **IP Neighbour Discovery** (which covers both LLDP and CDP), and any device that advertises itself — ESXi hosts, other switches, routers — will show up in the neighbour table with its hostname (identity). The information is already there on the switch; it's just not surfaced anywhere obvious in a persistent way. Interface comments are the natural place to put it, but updating them by hand every time something changes is tedious and inevitably falls behind.

---

## The Playbook: `update_interface_comments.yml`

The playbook runs in two plays. The first ensures the Python library `librouteros` is present on the Ansible controller (required by the `community.routeros.api` modules). The second does the actual work against the switches.

```yaml
---
- name: Ensure controller has librouteros
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Install librouteros pip package
      ansible.builtin.pip:
        name: librouteros
        state: present

- name: Update Mikrotik interface comments from LLDP/discovery neighbours
  hosts: mikrotik
  gather_facts: false
  ...
```

All RouterOS API calls share a common set of connection defaults via `module_defaults`, keeping the individual tasks clean:

```yaml
  module_defaults:
    group/community.routeros.api:
      hostname: "{{ ansible_host }}"
      username: "{{ ansible_user }}"
      password: "{{ ansible_password }}"
      tls: false
      validate_certs: false
```

### Step 1 — Fetch neighbours and interfaces

Two tasks pull data from the switch over the RouterOS API:

```yaml
    - name: Fetch discovery neighbours
      community.routeros.api:
        path: "ip neighbor"
      register: neighbours

    - name: Fetch interfaces
      community.routeros.api_info:
        path: interface
      register: interfaces
```

The neighbour table returns entries with fields like `interface`, `identity`, `address`, and `mac-address`. The interface list gives us every interface on the switch.

### Step 2 — Build a lookup map

A `set_fact` task distils the neighbour list down to a simple dictionary mapping interface name → neighbour identity:

```yaml
    - name: Build interface -> neighbour identity map
      ansible.builtin.set_fact:
        neighbour_map: >-
          {{
            dict(
              _items | map(attribute='interface')
              | zip(_items | map(attribute='identity'))
            )
          }}
      vars:
        _items: >-
          {{
            neighbours.msg
            | selectattr('interface', 'defined')
            | selectattr('identity', 'defined')
            | rejectattr('identity', 'equalto', '')
            | list
          }}
```

The filters here do a few important things:
- Only include neighbours that have both an `interface` and an `identity` field.
- Drop entries where `identity` is an empty string (devices that respond to discovery but don't broadcast a hostname).
- The result looks something like `{"qsfp28-1-2": "esxi-host-01", "qsfp28-1-3": "esxi-host-02"}`.

### Step 3 — Write LLDP comments back to interfaces

The main update task loops over every interface and, for any that appear in the neighbour map, writes a comment in the format `LLDP: <identity>`:

```yaml
    - name: Update interface comment from neighbour identity
      community.routeros.api_find_and_modify:
        path: interface
        find:
          name: "{{ item['name'] }}"
        values:
          comment: "{{ comment_prefix | default('LLDP') }}: {{ neighbour_map[item['name']] }}"
      loop: "{{ interfaces.result }}"
      loop_control:
        label: "{{ item['name'] }}"
      when:
        - item['name'] in (neighbour_map | default({}))
        - item['name'] not in (static_interface_comments | default({}))
        - item['name'] | regex_search('^(' + (skip_interfaces | default(['lo', 'bridge', 'vlan'])) | join('|') + ')') == none
```

Three `when` conditions control which interfaces get updated:

1. **Must have a neighbour** — skip interfaces with nothing plugged in or nothing advertising.
2. **Not in the static list** — interfaces with manually defined comments are left alone.
3. **Not a virtual interface** — logical interfaces (loopback, bridge, vlan) are skipped by default via `skip_interfaces`.

The `comment_prefix` variable defaults to `LLDP` but can be overridden per host if you want a different label format.

### Step 4 — Apply static overrides

Devices that don't speak LLDP (TrueNAS SCALE is a common example) need manual labels. A final task applies these from a per-host variable file, and because it runs *after* the LLDP pass, static comments always win:

```yaml
    - name: Apply static interface comments
      community.routeros.api_find_and_modify:
        path: interface
        find:
          name: "{{ item.key }}"
        values:
          comment: "{{ item.value }}"
      loop: "{{ static_interface_comments | default({}) | dict2items }}"
      loop_control:
        label: "{{ item.key }} -> {{ item.value }}"
```

---

## Variable Files

### `host_vars/mikrotik-sw-1/interface_comments.yml`

This is where static labels live for any port whose device doesn't advertise via LLDP:

```yaml
static_interface_comments:
  # Storage (no LLDP advertisement)
  qsfp28-1-4: "StoreServ1"
  qsfp28-2-4: "StoreServ2"

  # Workstations
  qsfp28-2-2: "Z840-1"
  qsfp28-2-3: "Z840-2"
```

Comments here are written verbatim — no `LLDP:` prefix is added. This lets you use whatever friendly label makes sense for the device.

---

## Running the Playbook

```bash
# Update all switches
ansible-playbook -i inventory.yml update_interface_comments.yml

# Update a single switch
ansible-playbook -i inventory.yml update_interface_comments.yml --limit mikrotik-sw-1
```

After it runs, opening **Interfaces** in Winbox or running `/interface print` in the RouterOS terminal will show the neighbour hostnames in the Comment column. The result is an always-current port map that updates itself whenever you re-run the playbook.

---

## Inventory

The playbook targets two MikroTik switches defined in `inventory.yml`:

| Host | IP Address |
|---|---|
| mikrotik-sw-1 | 192.168.3.1 |
| mikrotik-sw-2 | 192.168.3.2 |

Both connect via SSH key authentication using the `admin` user.

---

## Prerequisites

Install the required Ansible collections before running:

```bash
ansible-galaxy collection install community.routeros ansible.netcommon
pip install librouteros
```

The `librouteros` pip dependency is also handled automatically by the first play in the playbook, so it's covered even if you forget.

---

## Summary

The playbook does four things in sequence:

1. Queries the RouterOS neighbour table over the API.
2. Builds a map of interface → LLDP identity.
3. Writes `LLDP: <hostname>` comments to any interface that has a neighbour, skipping virtual interfaces and any port already covered by a static override.
4. Applies static comments for devices that don't advertise via LLDP.

The full playbook and variable files live in the [`ansible/mikrotik`](https://github.com/jameskilby/iac) repository alongside the backup and provisioning playbooks for the same switches.
