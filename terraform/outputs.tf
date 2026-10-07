output "vault_node_private_ips" {
  description = "Private IP addresses of the 3 Vault ACI nodes"
  value       = { for k, v in azurerm_network_interface.vault : k => v.private_ip_address }
}

output "vault_node_names" {
  description = "VM names of the 3 Vault ACI nodes"
  value       = [for vm in azurerm_linux_virtual_machine.vault : vm.name]
}

output "vault_load_balancer_ip" {
  description = "Private IP of the internal load balancer / VIP"
  value       = azurerm_lb.vault.private_ip_address
}

output "vault_cluster_api_url" {
  description = "Vault cluster API URL via load balancer"
  value       = "https://${azurerm_lb.vault.private_ip_address}:8200"
}
