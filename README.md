# vault-aci-modernization

Infrastructure-as-Code for the Vault OSS ACI cluster — Epic ITPIDP-1491.

Deploys a 3-node HashiCorp Vault OSS v1.21+ cluster on RHEL VMs in the Cisco ACI network,
with Raft HA storage and Azure KMS auto-unseal.

---

## Directory Structure

```
vault-aci-modernization/
├── terraform/                  # Azure VM + NIC + LB + disk provisioning
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── ansible/                    # Vault install, config, and service deployment
│   ├── inventory/sandbox.ini   # Update IPs when ACI VMs are provisioned
│   ├── group_vars/all.yml      # All config values — sourced from Track B audit
│   ├── roles/vault/
│   │   ├── tasks/main.yml
│   │   ├── templates/vault.hcl.j2
│   │   ├── templates/vault.service.j2
│   │   └── handlers/main.yml
│   └── site.yml
└── scripts/
    ├── bootstrap_raft.sh       # One-time Raft quorum initialisation
    └── validate_snapshot.sh    # Daily snapshot + Azure Blob upload
```

---

## Pre-Requisites Before Running

1. **ACI VMs provisioned** via ServiceNow (3x RHEL, 4 vCPU, 16 GB RAM, 100 GB)
2. **Update IPs** in `ansible/inventory/sandbox.ini` with actual ACI VM IPs
3. **TLS certificates** placed in `ansible/roles/vault/files/`:
   - `server.crt`, `server.key`, `ca.crt`
   - Request from QVC Enterprise CA (Venafi) — existing cert expires **Dec 2, 2026**
4. **Azure Managed Identity** assigned `Key Vault Crypto User` role on `Sandbox-vault-bf44f35d`
5. **Terraform tfvars** — copy `terraform.tfvars.example` to `terraform.tfvars` and fill in subnet ID

---

## Step-by-Step Execution

### 1 — Provision VMs (Terraform)
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### 2 — Deploy Vault (Ansible)
```bash
# Dry run first
ansible-playbook -i ansible/inventory/sandbox.ini ansible/site.yml --check

# Live deploy
ansible-playbook -i ansible/inventory/sandbox.ini ansible/site.yml
```

### 3 — Bootstrap Raft Quorum
```bash
# Update NODE IPs in the script first
chmod +x scripts/bootstrap_raft.sh
./scripts/bootstrap_raft.sh
```
Expected output: 3 nodes, all `Voter=true`

### 4 — Restore Snapshot from Existing Sandbox
```bash
# Take snapshot from existing leader (vault3 / 10.184.32.33)
export VAULT_ADDR="https://vault3.dev.wc.vault.qvcdev.qvc.net:8200"
export VAULT_CACERT="/vault/1.12.4/ca.crt"
/vault/vault operator raft snapshot save /tmp/sandbox_$(date +%Y%m%d).snap

# Restore onto new ACI leader
export VAULT_ADDR="https://vault-aci-01.qvcdev.qvc.net:8200"
export VAULT_CACERT="/vault/1.21.0/ca.crt"
/vault/vault operator raft snapshot restore -force /tmp/sandbox_$(date +%Y%m%d).snap
```

### 5 — Validate (16 secret engines + 7 auth methods must all be present)
```bash
/vault/vault secrets list
/vault/vault auth list
/vault/vault status
```

---

## Key Values (from Track B Audit — 10/6/2026)

| Parameter | Existing Sandbox | New ACI Cluster |
|---|---|---|
| Vault version | 1.12.4 | 1.21.0 |
| Cluster name | vault-ilc | vault-ilc |
| Node IPs | .31 / .32 / .33 | TBD (ACI subnet 10.184.32.0/22) |
| Leader (current) | vault3 / .33 | TBD after init |
| Azure KV name | Sandbox-vault-bf44f35d | Sandbox-vault-bf44f35d |
| Azure tenant | ff3213cc-c3f6-45d4-a104-8f7823656fec | same |
| Cert expiry | Dec 2, 2026 | New certs required |
| Auth method | client_secret in config | Managed Identity (no secret) |

---

## Security Improvements Over Existing Cluster

| Area | Existing | New ACI |
|---|---|---|
| Azure KMS auth | `client_secret` hardcoded in config | Azure Managed Identity — no secret |
| `SecureBits` | Commented out | Enabled (`keep-caps`) |
| `tls_prefer_server_cipher_suites` | `false` | `true` |
| Cert management | Manual | Via Venafi (`vault-pki-monitor-venafi_strict/`) |
