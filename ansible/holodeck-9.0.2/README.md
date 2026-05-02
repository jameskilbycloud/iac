# Holodeck 9.0.2 – Ansible Deployment

Ansible playbook to deploy a [VMware Holodeck 9.0.2](https://vmware.github.io/Holodeck/) nested VCF lab on a physical ESXi host. Holodeck provides a fully automated method to spin up a complete VMware Cloud Foundation environment inside a single physical hypervisor.

---

## What This Playbook Does

| Play | Actions |
|------|---------|
| **1 – Preflight** | Validates physical host has sufficient CPU, RAM, and storage; checks that the Holorouter OVA is present |
| **2 – Networking** | Creates the `VLC-A` vSwitch (no uplinks, 9000 MTU) and `VLC-A-PG` port group with promiscuous mode on the ESXi host |
| **3 – Holorouter** | Deploys the Holorouter OVA, powers it on, and waits for SSH to become available |
| **4 – VCF Lab** | SSHes into the Holorouter and executes `New-HoloDeckInstance` via PowerShell to build the nested VCF environment |

---

## Hardware Requirements

From the [official Holodeck documentation](https://vmware.github.io/Holodeck/downloads/):

| Deployment Type | CPU Cores | RAM | Storage |
|----------------|-----------|-----|---------|
| Single-site (default) | 24 physical cores | 384 GB | 2 TB |
| Dual-site | 32 physical cores | 1 TB | 4 TB |
| + VCF Automation (vSAN ESA) | 32+ vCPUs | 448+ GB | 2 TB+ |

> **Note:** Deploy Holodeck only on systems with sufficient physical RAM and with memory tiering **disabled** for a stable experience.

---

## Prerequisites

### 1. Ansible Collections

```bash
ansible-galaxy collection install community.vmware
```

### 2. Python Dependencies

```bash
pip install pyvmomi requests
```

### 3. Holorouter OVA

Download the Holorouter OVA for version 9.0.2 from the [Holodeck GitHub Releases](https://github.com/vmware/Holodeck/releases) page and place it in the `files/` directory:

```
holodeck-9.0.2/
└── files/
    └── holorouter-9.0.2.ova   ← place it here
```

### 4. VCF Component Downloads (for Online depot)

You will need a **Broadcom account with VCF entitlement** to generate an API token. Obtain one at [support.broadcom.com](https://support.broadcom.com). This token is used by the Holorouter to pull ESXi ISOs and the Cloud Builder/VCF Installer OVA directly during deployment.

For **offline (air-gapped)** deployments, set `holodeck_depot_type: "Offline"` in `group_vars/all.yml` and pre-stage the offline depot OVA on your datastore before running this playbook.

---

## Quick Start

### Step 1 – Clone / navigate to this directory

```bash
cd ansible/holodeck-9.0.2
```

### Step 2 – Create your Vault file

```bash
cp vault.yml.example vault.yml
ansible-vault encrypt vault.yml
# Edit to add real passwords/tokens:
ansible-vault edit vault.yml
```

### Step 3 – Update variables

Edit `group_vars/all.yml` to match your environment — at minimum:

- `esxi_host` – FQDN or IP of your physical ESXi host
- `esxi_datastore` – Target datastore name
- `holorouter_ip` / `holorouter_gateway` / `holorouter_dns` – Networking for the Holorouter VM
- `vlc_cidr` – A `/20` block for the nested lab fabric (default: `10.0.0.0/20`)

### Step 4 – Run the playbook

```bash
# With vault password prompt
ansible-playbook -i inventory.ini deploy-holodeck.yml --ask-vault-pass

# With a vault password file
ansible-playbook -i inventory.ini deploy-holodeck.yml --vault-password-file .vault_pass
```

> **Deployment time:** Play 4 (New-HoloDeckInstance) typically takes **60–120+ minutes** to complete. The playbook polls every 60 seconds and has a 3-hour async timeout.

---

## Configuration Reference

All variables live in `group_vars/all.yml`. Key options:

| Variable | Default | Description |
|----------|---------|-------------|
| `holodeck_instance_id` | `1` | Integer ID; allows multiple instances on one Holorouter |
| `holodeck_site` | `a` | `a` for single-site; `b` for second site in dual-site |
| `holodeck_vsan_mode` | `ESA` | `ESA` (Express Storage Architecture) or `OSA` |
| `holodeck_depot_type` | `Online` | `Online` or `Offline` |
| `vlc_cidr` | `10.0.0.0/20` | Must be a `/20` block; Holodeck subdivides it internally |
| `vlc_vlan_range_start` | `1000` | First VLAN in the nested lab range |
| `holodeck_deploy_vcf_automation` | `false` | Set `true` to also deploy VCF Automation |
| `holodeck_deploy_supervisor` | `false` | Set `true` to also deploy vSphere Supervisor |

---

## File Structure

```
holodeck-9.0.2/
├── deploy-holodeck.yml     # Main playbook (4 plays)
├── inventory.ini           # Inventory – localhost + holorouter group
├── vault.yml.example       # Vault template (copy → vault.yml, then encrypt)
├── group_vars/
│   └── all.yml             # All variables
├── files/
│   └── holorouter-9.0.2.ova  ← download and place here (not committed)
└── README.md
```

---

## Troubleshooting

**Preflight fails – not enough RAM/CPU**
Verify your physical host specifications. Memory tiering (e.g. Intel PMem, AMD CXL) must be disabled.

**OVA deploy fails – property mapping error**
The exact OVF property keys may differ between Holorouter releases. Inspect the OVA with `ovftool --examine holorouter-9.0.2.ova` and update the `properties` block in Play 3 accordingly.

**New-HoloDeckInstance hangs or fails**
SSH into the Holorouter directly and check `/var/log/holodeck/` or run `Get-HoloDeckStatus` in `pwsh` for real-time status.

**Broadcom API token rejected**
Ensure your Broadcom account has an active VCF subscription/entitlement and that the token was generated at [support.broadcom.com](https://support.broadcom.com).

---

## Related Resources

- [Holodeck Official Docs](https://vmware.github.io/Holodeck/)
- [Holodeck Downloads & Requirements](https://vmware.github.io/Holodeck/downloads/)
- [Holodeck GitHub Repository](https://github.com/vmware/Holodeck)
- [Holodeck 9.0.2 Release Announcement](https://blogs.vmware.com/cloud-foundation/2026/03/05/announcing-the-general-availability-of-holodeck-9-0-2/)
- [Ansible VMware Collection Docs](https://docs.ansible.com/ansible/latest/collections/community/vmware/)
- [Existing vSwitch Playbook](../holodeck/vSwitch.yml)
