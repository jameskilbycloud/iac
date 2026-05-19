# Terraform Infrastructure as Code

This directory contains Terraform configurations for managing VMware vSphere infrastructure and virtual machine deployments. The configurations are organized into infrastructure components and VM deployments, providing a comprehensive approach to infrastructure automation.

## Overview

These Terraform configurations enable automated provisioning and management of:
- **vSphere Infrastructure**: Datacenters, clusters, folders, roles, and content libraries
- **Virtual Machine Deployments**: Various VM types including specialized appliances
- **Resource Organization**: Structured folder hierarchy and resource pools
- **Content Management**: Template and OVA distribution via content libraries

## Directory Structure

```
terraform/
├── Infra/                    # vSphere infrastructure components
│   ├── vSphereContentLibrary/  # Content library management
│   ├── vSphereFolders/         # VM folder organization
│   ├── vSphereRoles/           # vSphere role definitions
│   └── vSphereVCSetup/         # vCenter and cluster setup
└── VM/                       # Virtual machine deployments
    ├── Deploy-FAH/            # Folding@Home appliance deployment
    └── VMCLogs/               # Photon VM for logging
```

## Infrastructure Components (Infra/)

### 🏗️ vSphere Content Library (`Infra/vSphereContentLibrary/`)

**Purpose**: Manages vSphere content libraries for template and OVA distribution.

**Features**:
- Creates publisher content libraries
- Configures storage backing with vSAN
- Enables library publication for sharing
- Supports multiple library types (packer, manual images)

**Resources Created**:
- `packer` content library for automated builds
- `manualimages` content library for custom templates

**Usage**:
```bash
cd Infra/vSphereContentLibrary/
terraform init
terraform plan
terraform apply
```

### 📁 vSphere Folders (`Infra/vSphereFolders/`)

**Purpose**: Creates organized folder hierarchy for VM management.

**Features**:
- Production environment folders
- Test environment structure
- Specialized folders for different workloads
- Holodeck test environment support

**Folder Structure**:
```
Production/
├── Active Directory/
├── IAC/
├── Aria/
└── Horizon/

Test/
├── HoloDeck/
└── Docker/
```

**Usage**:
```bash
cd Infra/vSphereFolders/
terraform init
terraform plan
terraform apply
```

### 🔐 vSphere Roles (`Infra/vSphereRoles/`)

**Purpose**: Defines custom vSphere roles with specific privileges.

**Features**:
- Creates Packer-specific roles
- Configurable privilege sets
- Supports secure automation workflows
- Example configuration provided

**Configuration**:
- Role name: `packer-vsphere`
- Privileges: Configurable via variables
- Example file: `terraform.tfvars.example`

**Usage**:
```bash
cd Infra/vSphereRoles/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration
terraform init
terraform plan
terraform apply
```

### 🏢 vSphere vCenter Setup (`Infra/vSphereVCSetup/`)

**Purpose**: Configures vCenter datacenters and compute clusters.

**Features**:
- Creates production datacenters
- Configures compute clusters with DRS and HA
- Sets up fully automated resource management
- Supports multiple cluster configurations

**Resources Created**:
- Datacenter: `uk-bhr-p-dc-1`
- Clusters: `uk-bhr-p-cl-1`, `uk-bhr-p-cl-2`
- DRS: Fully automated
- HA: Enabled

**Usage**:
```bash
cd Infra/vSphereVCSetup/
terraform init
terraform plan
terraform apply
```

## Virtual Machine Deployments (VM/)

### 🧬 Folding@Home Appliance (`VM/Deploy-FAH/`)

**Purpose**: Deploys VMware Folding@Home appliance for distributed computing.

**Features**:
- Modular design with separate components
- Supports both local and remote OVA deployment
- Configurable FAH user and team settings
- Automatic resource pool and folder creation
- DHCP network configuration

**Components**:
- **Folder Module**: Creates VM folder structure
- **Resource Pool Module**: Sets up resource pools
- **FAH Appliance Module**: Deploys the actual VM

**Configuration**:
- **Tested**: VMware Cloud on AWS, Terraform v0.13.5, vSphere provider 1.23.0
- **Known Issue**: vSphere provider 1.24.0+ compatibility issue
- **Network**: DHCP-enabled networks

**Usage**:
```bash
cd VM/Deploy-FAH/
# Edit terraform.tfvars with your configuration
terraform init
terraform plan
terraform apply
```

**Prerequisites**:
- Folding@Home OVA file (local or remote)
- FAH user account and team ID
- vSphere environment with appropriate permissions

### 📊 VMCLogs Photon VM (`VM/VMCLogs/`)

**Purpose**: Deploys Photon OS VM from content library for logging and monitoring.

**Features**:
- Content library-based deployment
- Photon OS template utilization
- Static IP configuration
- Custom hostname and domain setup
- Resource-efficient deployment

**Specifications**:
- **CPU**: 2 vCPUs
- **Memory**: 2GB RAM
- **Storage**: 16GB thin-provisioned
- **OS**: Photon OS (other3xLinux64Guest)
- **Network**: Static IP configuration

**Configuration**:
- **Template**: Content library OVA
- **Customization**: Linux options with static IP
- **DNS**: Configurable DNS servers
- **Gateway**: Static gateway configuration

**Usage**:
```bash
cd VM/VMCLogs/
# Configure terraform.tfvars with network details
terraform init
terraform plan
terraform apply
```

## Prerequisites

### Required Software
- **Terraform**: >= 1.0.0
- **vSphere Provider**: >= 2.2.0 (varies by module)
- **vSphere Environment**: ESXi/vCenter access

### Required Permissions
- **vSphere Administrator** or equivalent role
- **Datacenter management** permissions
- **VM creation** and **template deployment** rights
- **Content library** management permissions

### Network Requirements
- **vSphere connectivity** from Terraform execution host
- **DHCP network** for FAH deployment
- **Static IP configuration** for VMCLogs
- **Content library access** for template deployment

## Configuration

### Provider Configuration
All modules use the vSphere provider with similar configuration:
```hcl
provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}
```

### Variable Management
- **Sensitive data**: Use environment variables or secure variable files
- **Environment-specific**: Create separate `.tfvars` files for different environments
- **Validation**: Use variable validation blocks where appropriate

### State Management
- **Local state**: Default for development
- **Remote state**: Recommended for production (configure backend)
- **State locking**: Enable for team environments

## Security Considerations

### 🔒 Access Control
- **Role-based access**: Use vSphere roles for least privilege
- **Credential management**: Never commit passwords to version control
- **Network security**: Use VPN or secure networks for management
- **Certificate validation**: Enable SSL verification in production

### 🛡️ Infrastructure Security
- **Resource isolation**: Use separate folders and resource pools
- **Network segmentation**: Implement proper VLANs and firewalls
- **Backup strategies**: Regular state and configuration backups
- **Audit logging**: Monitor infrastructure changes

## Best Practices

### Infrastructure Organization
1. **Deploy infrastructure first**: Run Infra/ modules before VM deployments
2. **Use consistent naming**: Follow established naming conventions
3. **Implement tagging**: Use vSphere tags for resource organization
4. **Version control**: Track all configuration changes

### Deployment Workflow
1. **Plan before apply**: Always review changes with `terraform plan`
2. **Test in development**: Validate configurations in test environment
3. **Use workspaces**: Separate state for different environments
4. **Monitor deployments**: Track resource creation and configuration

### Maintenance
1. **Regular updates**: Keep Terraform and provider versions current
2. **State cleanup**: Remove unused resources and state entries
3. **Documentation**: Update README files with configuration changes
4. **Backup verification**: Test restore procedures regularly

## Troubleshooting

### Common Issues

#### Provider Version Conflicts
```
Error: Incompatible provider version
```
**Solution**: Update provider versions in `versions.tf` files

#### Authentication Failures
```
Error: Authentication failed
```
**Solution**: Verify vSphere credentials and permissions

#### Resource Dependencies
```
Error: Resource not found
```
**Solution**: Ensure infrastructure components are deployed first

#### State Conflicts
```
Error: State file locked
```
**Solution**: Check for concurrent operations or force unlock if necessary

### Debugging Commands
```bash
# Validate configuration
terraform validate

# Check syntax
terraform fmt -check

# Show current state
terraform show

# List resources
terraform state list

# Import existing resources
terraform import <resource> <id>
```

## Integration with Other Tools

### Ansible Integration
- **Post-deployment configuration**: Use Ansible for VM configuration
- **Application deployment**: Deploy applications after VM creation
- **Monitoring setup**: Configure monitoring and logging

### Packer Integration
- **Template creation**: Use Packer to create VM templates
- **Content library**: Store templates in vSphere content libraries
- **Automated builds**: Integrate with CI/CD pipelines

### Monitoring and Logging
- **vRealize Operations**: Monitor infrastructure health
- **vRealize Log Insight**: Centralized logging
- **Custom dashboards**: Build monitoring dashboards

## Contributing

When adding new Terraform configurations:

1. **Follow naming conventions**: Use consistent resource naming
2. **Implement modules**: Create reusable modules for common patterns
3. **Add documentation**: Include README files for each module
4. **Test thoroughly**: Validate in test environment before production
5. **Update this README**: Document new modules and configurations

## Support

For issues and questions:

- **Terraform Documentation**: [terraform.io/docs](https://terraform.io/docs)
- **vSphere Provider**: [registry.terraform.io/providers/vmware/vsphere](https://registry.terraform.io/providers/vmware/vsphere)
- **VMware Documentation**: [docs.vmware.com](https://docs.vmware.com)
- **Project Issues**: Use the main project repository

## License

This project follows the same license as the parent repository. Please refer to the main project documentation for licensing information. 