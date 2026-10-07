variable "resource_group_name" {
  description = "Azure Resource Group where the ACI VMs reside"
  type        = string
}

variable "location" {
  description = "Azure region (e.g. eastus2, westcentralus)"
  type        = string
  default     = "eastus2"
}

variable "vm_names" {
  description = "Names for the 3 Vault ACI nodes"
  type        = list(string)
  default     = ["vault-aci-01", "vault-aci-02", "vault-aci-03"]
}

variable "vm_size" {
  description = "Azure VM size — 4 vCPU, 16 GB RAM per spec"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "admin_username" {
  description = "OS admin username for the VMs"
  type        = string
  default     = "vault"
}

variable "subnet_id" {
  description = "Subnet ID for the ACI network (10.184.32.0/22)"
  type        = string
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 100
}

variable "vault_data_disk_size_gb" {
  description = "Dedicated data disk size for /opt/vault/data"
  type        = number
  default     = 100
}

variable "vault_version" {
  description = "Target Vault OSS version to install"
  type        = string
  default     = "1.21.0"
}

variable "azure_keyvault_name" {
  description = "Azure Key Vault name used for auto-unseal (existing sandbox: Sandbox-vault-bf44f35d)"
  type        = string
}

variable "azure_kms_key_name" {
  description = "Azure Key Vault key name for auto-unseal (existing sandbox: generated-key)"
  type        = string
  default     = "generated-key"
}

variable "azure_tenant_id" {
  description = "Azure AD tenant ID (existing sandbox: ff3213cc-c3f6-45d4-a104-8f7823656fec)"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    project     = "ITPIDP-1491"
    environment = "sandbox"
    managed_by  = "terraform"
    component   = "vault-aci"
  }
}
