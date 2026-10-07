terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
data "azurerm_subnet" "vault" {
  # Subnet: 10.184.32.0/22 — ACI network assigned for Vault servers (spk/eqx)
  # Provide the subnet_id in terraform.tfvars
  id = var.subnet_id
}

# ---------------------------------------------------------------------------
# Network interfaces — one per node
# ---------------------------------------------------------------------------
resource "azurerm_network_interface" "vault" {
  for_each            = toset(var.vm_names)
  name                = "nic-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = data.azurerm_subnet.vault.id
    private_ip_address_allocation = "Dynamic"
  }
}

# ---------------------------------------------------------------------------
# Internal load balancer — VIP for Vault API (port 8200)
# Health probe: GET /v1/sys/health
# ---------------------------------------------------------------------------
resource "azurerm_lb" "vault" {
  name                = "lb-vault-aci-sandbox"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                          = "vault-frontend"
    subnet_id                     = data.azurerm_subnet.vault.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "vault" {
  loadbalancer_id = azurerm_lb.vault.id
  name            = "vault-backend-pool"
}

resource "azurerm_lb_probe" "vault" {
  loadbalancer_id     = azurerm_lb.vault.id
  name                = "vault-health"
  protocol            = "Https"
  port                = 8200
  request_path        = "/v1/sys/health"
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "vault_api" {
  loadbalancer_id                = azurerm_lb.vault.id
  name                           = "vault-api-8200"
  protocol                       = "Tcp"
  frontend_port                  = 8200
  backend_port                   = 8200
  frontend_ip_configuration_name = "vault-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.vault.id]
  probe_id                       = azurerm_lb_probe.vault.id
}

resource "azurerm_network_interface_backend_address_pool_association" "vault" {
  for_each                = toset(var.vm_names)
  network_interface_id    = azurerm_network_interface.vault[each.key].id
  ip_configuration_name   = "ipconfig"
  backend_address_pool_id = azurerm_lb_backend_address_pool.vault.id
}

# ---------------------------------------------------------------------------
# Virtual Machines — 3 nodes (RHEL, 4 vCPU, 16 GB RAM, 100 GB OS disk)
# Image: Red Hat Enterprise Linux from Red Hat registry (UBI-based marketplace)
# ---------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "vault" {
  for_each            = toset(var.vm_names)
  name                = each.key
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username
  tags                = var.tags

  # Non-root SSH key authentication — no password login
  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub")
  }

  network_interface_ids = [azurerm_network_interface.vault[each.key].id]

  # Azure Managed Identity — used by Vault for Azure KMS auto-unseal
  # No client_secret needed in vault_main.hcl
  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  # RHEL 9 from official Red Hat marketplace image
  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "9-lvm-gen2"
    version   = "latest"
  }
}

# ---------------------------------------------------------------------------
# Dedicated data disk for /vault/ (Raft storage)
# Separate disk ensures Raft data survives OS disk replacement
# ---------------------------------------------------------------------------
resource "azurerm_managed_disk" "vault_data" {
  for_each             = toset(var.vm_names)
  name                 = "disk-${each.key}-vault-data"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.vault_data_disk_size_gb
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "vault_data" {
  for_each           = toset(var.vm_names)
  managed_disk_id    = azurerm_managed_disk.vault_data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.vault[each.key].id
  lun                = 0
  caching            = "ReadWrite"
}

# ---------------------------------------------------------------------------
# Key Vault Crypto User role — grants each VM Managed Identity permission
# to use the Azure KMS key for auto-unseal
# ---------------------------------------------------------------------------
data "azurerm_key_vault" "unseal" {
  name                = var.azure_keyvault_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_role_assignment" "vault_kv_crypto" {
  for_each             = toset(var.vm_names)
  scope                = data.azurerm_key_vault.unseal.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_linux_virtual_machine.vault[each.key].identity[0].principal_id
}
