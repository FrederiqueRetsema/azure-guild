variable "resource_group_name" {
  description = "Name of the resource group to deploy the AKS cluster into."
  type        = string
}

variable "location" {
  description = "Azure region to deploy resources into."
  type        = string
  default     = "westeurope"
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "azure-guild-aks"
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster API server."
  type        = string
  default     = "azure-guild"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster. Leave null to use the AKS default."
  type        = string
  default     = null
}

variable "node_count" {
  description = "Number of nodes in the default node pool."
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for the default node pool nodes."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project = "azure-guild"
    managed = "terraform"
    owner   = "Frederique"
  }
}

# --- ArgoCD ---

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed."
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart (argoproj/argo-helm)."
  type        = string
  default     = "8.3.0"
}

# --- ArgoCD Application ---

variable "argocd_app_name" {
  description = "Name of the ArgoCD Application."
  type        = string
  default     = "guild-app"
}

variable "github_repo_url" {
  description = "GitHub repository URL that the ArgoCD Application tracks."
  type        = string
}

variable "github_repo_revision" {
  description = "Git revision (branch, tag, or commit) the ArgoCD Application tracks."
  type        = string
  default     = "HEAD"
}

variable "github_repo_path" {
  description = "Path within the repository that contains the Kubernetes/Helm manifests."
  type        = string
  default     = "guild-app"
}

variable "argocd_app_namespace" {
  description = "Destination namespace in the cluster where the ArgoCD Application deploys resources."
  type        = string
  default     = "default"
}

variable "nodeport" {
  description = "NodePort to expose to the public internet (must match the Kubernetes Service nodePort)."
  type        = number
  default     = 30080
}

variable "nodeport_source_address_prefix" {
  description = "Source CIDR allowed to reach the NodePort. Use \"*\"/\"Internet\" for the whole internet, or restrict to your own IP."
  type        = string
  default     = "Internet"
}

# --- ArgoCD public NodePort access ---

variable "argocd_nodeport_http" {
  description = "NodePort for the ArgoCD server HTTP port."
  type        = number
  default     = 30081
}

variable "argocd_nodeport_https" {
  description = "NodePort for the ArgoCD server HTTPS port."
  type        = number
  default     = 30082
}

variable "crossplane_namespace" {
  description = "Namespace where Crossplane is installed."
  type        = string
  default     = "crossplane-system"
}

variable "crossplane_chart_version" {
  description = "Version of the crossplane Helm chart (charts.crossplane.io/stable)."
  type        = string
  default     = "2.4.3"
}

# --- Crossplane Azure provider ---

variable "crossplane_azure_provider_version" {
  description = "Version tag for the Upbound Azure family/service provider packages (xpkg.upbound.io/upbound/provider-azure-*)."
  type        = string
  default     = "v2.8.0"
}

variable "crossplane_azure_service_providers" {
  description = "List of Upbound Azure service provider packages to install (short names, e.g. \"resources\", \"network\"). The provider-family package is always installed as their dependency."
  type        = list(string)
  default     = ["resources", "network", "storage"]
}

variable "crossplane_azure_credentials_json" {
  description = <<-EOT
    Azure service principal credentials JSON used by the Crossplane Azure
    ProviderConfig (the output of `az ad sp create-for-rbac --sdk-auth ...`).
    Leave empty to skip creating the credentials Secret and ProviderConfig; you
    can create them later by hand. Keep this out of version control (set it via
    an environment variable TF_VAR_crossplane_azure_credentials_json or a
    gitignored .tfvars file).
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "crossplane_azure_providerconfig_name" {
  description = "Name of the Crossplane Azure ProviderConfig."
  type        = string
  default     = "default"
}
