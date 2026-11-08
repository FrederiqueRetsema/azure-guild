# Copy to terraform.tfvars and adjust as needed.

# Required
github_repo_url     = "https://github.com/FrederiqueRetsema/azure-guild.git"
resource_group_name = "frederique-azure-guild"

# Optional overrides (defaults shown).
# location             = "westeurope"
# cluster_name         = "azure-guild-aks"
# node_count           = 2
# node_vm_size         = "Standard_D2s_v5"
# kubernetes_version   = null

# github_repo_revision = "HEAD"
# argocd_app_namespace = "default"
# argocd_chart_version = "8.3.0"

# Crossplane Azure service providers. Includes "dbformysql" so the MySQL
# Flexible Server managed resources in ../crossplane-managed-resource work.
# crossplane_azure_service_providers = ["resources", "network", "storage", "dbformysql"]
