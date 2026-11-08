data "azurerm_resources" "aks_node_nsg" {
  resource_group_name = azurerm_kubernetes_cluster.this.node_resource_group
  type                = "Microsoft.Network/networkSecurityGroups"

  depends_on = [azurerm_kubernetes_cluster.this]
}

# The NSG is also needed when only the ArgoCD NodePort is exposed, so look it up
# whenever either NodePort feature is enabled.
data "azurerm_resources" "aks_node_nsg_argocd" {
  resource_group_name = azurerm_kubernetes_cluster.this.node_resource_group
  type                = "Microsoft.Network/networkSecurityGroups"

  depends_on = [azurerm_kubernetes_cluster.this]
}

locals {
  # Name of the AKS-managed node NSG, resolved from whichever lookup is active.
  aks_node_nsg_name = try(data.azurerm_resources.aks_node_nsg.resources[0].name, null)
}

# Allow inbound traffic to the app NodePort from the configured source.
resource "azurerm_network_security_rule" "nodeport" {
  name                        = "allow-nodeport-${var.guildapp_nodeport_http}"
  resource_group_name         = azurerm_kubernetes_cluster.this.node_resource_group
  network_security_group_name = local.aks_node_nsg_name

  priority                   = 1001
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = tostring(var.guildapp_nodeport_http)
  source_address_prefix      = var.nodeport_source_address_prefix
  destination_address_prefix = "*"
}

# Allow inbound traffic to the ArgoCD server NodePorts (HTTP + HTTPS).
resource "azurerm_network_security_rule" "argocd_nodeport" {
  name                        = "allow-argocd-nodeport"
  resource_group_name         = azurerm_kubernetes_cluster.this.node_resource_group
  network_security_group_name = local.aks_node_nsg_name

  priority                   = 1002
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_ranges    = [tostring(var.argocd_nodeport_http), tostring(var.argocd_nodeport_https)]
  source_address_prefix      = var.nodeport_source_address_prefix
  destination_address_prefix = "*"
}
