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

## Gotcha: Intel X710/XL710/XXV710 NICs Advertise Their Own Firmware LLDP

If some interfaces show a neighbour in `/ip neighbor` but never pick up a comment, check the `identity` field before assuming the playbook is broken. On a few of my ESXi hosts (Nutanix nodes with Intel XXV710 25GbE adapters), the switch happily reports a neighbour on the port — `discovered-by: lldp` — but with an empty `identity` and `platform`. The playbook's mapping step deliberately does `rejectattr('identity', 'equalto', '')`, so it correctly skips writing a comment rather than labelling the port with nothing useful. That's working as intended; the real problem is upstream.

Intel's X710/XL710/XXV710 family runs its own LLDP agent inside the adapter firmware, independent of whatever Discovery Protocol setting you pick on the ESXi vSwitch or vDS. That firmware agent only sends the mandatory TLVs — Chassis ID and Port ID — with no System Name, which is exactly the blank-identity pattern above. Flipping the vSphere-side setting between CDP and LLDP (or Listen/Advertise/Both) has no effect on these frames at all, because vSphere isn't the one sending them.

The fix lives on the ESXi host, not the switch or vCenter: disable the firmware LLDP agent via the `i40en` driver module parameter (one bit per port, across all Intel NICs on the host):

```bash
esxcli system module parameters set -m i40en -p "LLDP=0,0,0,0"
```

Reboot the host (or reload the driver) for it to take effect. With the firmware agent silenced, whatever Discovery Protocol you've configured on the ESXi vSwitch/vDS becomes the only thing advertising on that link. Which protocol to pick, though, turned out to depend on the switch — see the next gotcha.

---

## Gotcha: CDP Didn't Work At All — It's a Hardware Switching Problem, Not an ESXi One

After disabling the firmware LLDP agent above, I set the ESXi distributed switch's Discovery Protocol to CDP with Operation: Both — the usual recommendation, since ESXi's own CDP implementation is generally more consistent than its LLDP support, which varies by NIC vendor. I even disabled and re-enabled it in vCenter to force a clean re-apply. Nothing showed up in `/ip neighbor` at all — not even a blank-identity entry like the firmware LLDP produced. Whatever left the ESXi host, the switch never saw a single CDP frame arrive.

The cause turned out to be entirely on the switch side, and specific to how its ASIC does **hardware switching**. This MikroTik bridge (`br-vcf`) has hardware offloading enabled (`hw=yes` on every bridge port, set by this playbook's provisioning role for performance) — meaning most frames are forwarded directly by the switch chip and never touch the CPU at all. Whether a given multicast destination gets *trapped* to the CPU for software processing (which is what neighbour discovery needs) or just switched in hardware like ordinary traffic depends on the destination MAC address:

- **LLDP** uses `01:80:c2:00:00:0e`, part of the IEEE 802.1Q reserved multicast range that switch silicon is required to trap to the CPU for link-layer control-plane processing — this is why the firmware LLDP frames showed up immediately, blank identity and all.
- **CDP** uses `01:00:0c:cc:cc:cc`, a Cisco-proprietary address with no such guarantee. With hardware switching enabled, this switch's ASIC just forwards/floods it like any other multicast frame instead of delivering it to RouterOS's neighbour-discovery process on the CPU.

Switching the vDS's Discovery Protocol Type from CDP to LLDP (keeping Operation: Both) fixed it immediately — every previously silent or blank-identity port resolved to a real hostname on the very next check. So the practical takeaway is the opposite of the usual ESXi advice: on switches that hardware-offload their bridging (which includes most MikroTik CRS/CCR gear, not just this one), prefer **LLDP** over CDP for Discovery Protocol, because the bottleneck isn't ESXi's implementation quality at all — it's whether the switch's hardware switching path even lets the frame reach the software that's supposed to read it.

---

## Summary

The playbook does four things in sequence:

1. Queries the RouterOS neighbour table over the API.
2. Builds a map of interface → LLDP identity.
3. Writes `LLDP: <hostname>` comments to any interface that has a neighbour, skipping virtual interfaces and any port already covered by a static override.
4. Applies static comments for devices that don't advertise via LLDP.

The full playbook and variable files live in the [`ansible/mikrotik`](https://github.com/jameskilby/iac) repository alongside the backup and provisioning playbooks for the same switches.
