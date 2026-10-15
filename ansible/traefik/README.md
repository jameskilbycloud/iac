# Traefik Deployment with Ansible

Automated deployment of Traefik reverse proxy with Cloudflare SSL wildcard certificates on Ubuntu/Debian hosts.

## Features

- ✅ Automated Traefik deployment via Docker
- ✅ Cloudflare DNS challenge for SSL certificates
- ✅ Wildcard certificate support (`*.domain.com`)
- ✅ Traefik dashboard with basic authentication
- ✅ Health checks and monitoring
- ✅ Test service deployment for validation
- ✅ Automatic HTTP to HTTPS redirection

## Prerequisites

### Control Machine (Local)
- Ansible 2.9+
- SSH access to target host(s)

### Target Host
- Ubuntu/Debian operating system
- Docker and Docker Compose installed
- SSH access with sudo privileges
- Ports 80 and 443 available

### Cloudflare
- Cloudflare account with domain configured
- API token with DNS edit permissions for your domain
- DNS records pointing to your server

## Quick Start

### 1. Install Ansible Collections

```bash
ansible-galaxy collection install community.docker
```

### 2. Create Inventory File

Create `inventory.ini`:

```ini
[traefik_servers]
your-server.example.com ansible_user=your_username
```

### 3. Create Variables File

Create `vars.yml` with your configuration:

```yaml
# Traefik Configuration
traefik_image: "traefik:v3.6.1"
traefik_container_name: "traefik"
traefik_network: "traefik"
traefik_config_dir: "/opt/traefik"
traefik_cert_dir: "/opt/traefik/acme"

# Ports
traefik_port_web: 80
traefik_port_websecure: 443

# Wildcard Certificate Configuration
wildcard_domain: "example.com"  # Base domain for wildcard cert

# Cloudflare API Token
cloudflare_api_token: "your_cloudflare_api_token_here"

# ACME Configuration
acme_delay_before_check: 30
dns_resolvers:
  - "1.1.1.1:53"
  - "8.8.8.8:53"

# Dashboard Configuration
dashboard_domain: "traefik.example.com"
dashboard_admin_user: "admin"
dashboard_admin_password_hash: "$2y$05$..."  # Generate with: htpasswd -nB admin

# Test Service
test_service_name: "nginx-test"
test_service_image: "nginx:alpine"
test_service_domain: "test.example.com"

# Logging
log_level: "INFO"
log_format: "json"
log_max_size: "10m"
log_max_files: "3"

# Health Check
healthcheck_interval: "30s"
healthcheck_timeout: "5s"
healthcheck_retries: 3
healthcheck_start_period: "10s"
```

### 4. Generate Dashboard Password Hash

```bash
# Install apache2-utils if needed
sudo apt-get install apache2-utils

# Generate password hash
htpasswd -nB admin
# Copy the output (including "admin:") to dashboard_admin_password_hash
```

### 5. Validate Cloudflare Token (Optional)

```bash
ansible-playbook -i inventory.ini validate_cloudflare_token.yml
```

### 6. Deploy Traefik

```bash
ansible-playbook -i inventory.ini -e @vars.yml traefik_deploy.yml
```

## Wildcard Certificate Configuration

The playbook automatically configures Traefik to request a wildcard certificate for your domain using Cloudflare DNS challenge.

### How It Works

1. **Wildcard Router**: Automatically requests a certificate for `*.example.com` and `example.com`
2. **DNS Challenge**: Uses Cloudflare API to validate domain ownership
3. **Automatic Application**: All services use the wildcard certificate by default
4. **No Rate Limits**: Single certificate eliminates Let's Encrypt rate limit issues

### Service Configuration

Services deployed after Traefik will automatically use the wildcard certificate. Just set `tls: true`:

```yaml
labels:
  traefik.enable: "true"
  traefik.http.routers.myapp.rule: "Host(`myapp.example.com`)"
  traefik.http.routers.myapp.entrypoints: "websecure"
  traefik.http.routers.myapp.tls: "true"  # Uses wildcard cert
  traefik.http.services.myapp.loadbalancer.server.port: "8080"
```

**Do NOT specify** `traefik.http.routers.myapp.tls.certresolver: "cloudflare"` when using wildcard certificates.

## Post-Deployment

### 1. Verify Traefik is Running

```bash
ansible traefik_servers -i inventory.ini -m shell -a "docker ps | grep traefik"
```

### 2. Check Traefik Logs

```bash
ansible traefik_servers -i inventory.ini -m shell -a "docker logs traefik"
```

### 3. Verify Wildcard Certificate

```bash
ssh your-server.example.com
docker exec traefik cat /acme/acme.json | python3 -c "import json, sys; data=json.load(sys.stdin); certs=data['cloudflare']['Certificates']; [print(c['domain']) for c in certs]"
```

Look for:
```json
{'main': 'example.com', 'sans': ['*.example.com']}
```

### 4. Access Dashboard

Visit `https://traefik.example.com` and login with your credentials.

### 5. Test Service

Visit `https://test.example.com` to verify the test nginx service is accessible with SSL.

## File Structure

```
/opt/traefik/
├── traefik.yml       # Static configuration
├── dynamic.yml       # Dynamic configuration (dashboard, wildcard cert)
└── acme/
    └── acme.json     # SSL certificates storage
```

## Variables Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `cloudflare_api_token` | Cloudflare API token with DNS edit permissions | `abc123...` |
| `wildcard_domain` | Base domain for wildcard certificate | `example.com` |
| `dashboard_domain` | Domain for Traefik dashboard | `traefik.example.com` |
| `dashboard_admin_password_hash` | Bcrypt hash of dashboard password | `$2y$05$...` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `traefik_image` | `traefik:v3.6.1` | Traefik Docker image |
| `traefik_network` | `traefik` | Docker network name |
| `traefik_config_dir` | `/opt/traefik` | Configuration directory |
| `log_level` | `INFO` | Log level (DEBUG, INFO, WARN, ERROR) |
| `acme_delay_before_check` | `30` | DNS propagation delay (seconds) |
| `traefik_read_timeout` | `3600s` | Max time to read a whole request including the body on `websecure`. Traefik's own default is `60s`, which breaks large uploads such as the [VCF offline bundle server](../VCF/README.md). `0` disables the limit |
| `traefik_idle_timeout` | `180s` | Keep-alive idle timeout on `websecure` |

## Troubleshooting

### Certificate Not Issued

**Check Cloudflare token:**
```bash
ansible-playbook -i inventory.ini validate_cloudflare_token.yml
```

**Check Traefik logs for ACME errors:**
```bash
docker logs traefik 2>&1 | grep -i "acme\|certificate\|error"
```

**Verify token environment variable:**
```bash
docker exec traefik env | grep CF_DNS_API_TOKEN
```

### Rate Limited by Let's Encrypt

If you hit rate limits before deploying wildcard:
```bash
# Check when you can retry
docker logs traefik 2>&1 | grep "retry after"
```

Wait 3 hours or configure Let's Encrypt staging environment for testing.

### Dashboard Not Accessible

**Verify DNS:**
```bash
dig traefik.example.com
```

**Check router configuration:**
```bash
docker exec traefik cat /etc/traefik/dynamic.yml
```

**Verify container is healthy:**
```bash
docker inspect traefik | grep -A 10 Health
```

### Service Not Getting SSL

1. Ensure service is on the `traefik` network
2. Remove any `certresolver` labels from service
3. Set `traefik.http.routers.<name>.tls: "true"`
4. Restart service: `docker restart <service-name>`
5. Wait 1-2 minutes for configuration reload

## Security Considerations

- **Cloudflare Token**: Store securely, use Ansible Vault for production
- **Dashboard Password**: Use strong password and bcrypt hashing
- **Docker Socket**: Mounted read-only to limit container permissions
- **ACME Storage**: Restricted to root:root with 0600 permissions
- **Network Isolation**: Services must be on traefik network to be exposed

## Ansible Vault Usage

Encrypt sensitive variables:

```bash
# Create encrypted vars file
ansible-vault create vault.yml

# Add:
cloudflare_api_token: "your_token_here"
dashboard_admin_password_hash: "$2y$05$..."

# Deploy with vault
ansible-playbook -i inventory.ini -e @vars.yml -e @vault.yml --ask-vault-pass traefik_deploy.yml
```

## Maintenance

### Update Traefik Version

1. Edit `vars.yml` and change `traefik_image`
2. Re-run playbook:
```bash
ansible-playbook -i inventory.ini -e @vars.yml traefik_deploy.yml
```

### Backup Certificates

```bash
ansible traefik_servers -i inventory.ini -m fetch \
  -a "src=/opt/traefik/acme/acme.json dest=./backups/ flat=yes"
```

### View Certificate Expiry

```bash
docker exec traefik cat /acme/acme.json | python3 -c "
import json, sys
from datetime import datetime
data = json.load(sys.stdin)
for cert in data['cloudflare']['Certificates']:
    print(f\"Domain: {cert['domain']}\")
    print(f\"Expires: {cert['certificate']['NotAfter']}\")
"
```

## Additional Resources

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Docker Networks](https://docs.docker.com/network/)

## Support Files

- `traefik_deploy.yml` - Main deployment playbook
- `validate_cloudflare_token.yml` - Token validation playbook

## License

Use according to your organization's policies.
