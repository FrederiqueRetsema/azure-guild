variable "region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "aws-guild-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster. Leave null to use the EKS default."
  type        = string
  default     = "1.37"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Two /24 public subnets are carved out of it."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_count" {
  description = "Number of nodes in the managed node group."
  type        = number
  default     = 2
}

variable "node_instance_type" {
  description = "EC2 instance type for the node group nodes."
  type        = string
  default     = "t3.medium"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project = "aws-guild"
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

variable "argocd_app_namespace" {
  description = "Destination namespace in the cluster where the ArgoCD Application deploys resources."
  type        = string
  default     = "default"
}

variable "crossplane_managed_resource_path" {
  description = "Path in the GitHub repository with the Crossplane managed resources. The default directory contains Azure resources; point this to AWS manifests when deploying on AWS."
  type        = string
  default     = "crossplane-managed-resource"
}

variable "guildapp_nodeport_http" {
  description = "NodePort to expose to the public internet (must match the Kubernetes Service nodePort)."
  type        = number
  default     = 30082
}

variable "nodeport_source_cidr" {
  description = "Source CIDR allowed to reach the NodePorts. Use 0.0.0.0/0 for the whole internet, or restrict to your own IP."
  type        = string
  default     = "0.0.0.0/0"
}

# --- ArgoCD public NodePort access ---

variable "argocd_nodeport_http" {
  description = "NodePort for the ArgoCD server HTTP port."
  type        = number
  default     = 30080
}

variable "argocd_nodeport_https" {
  description = "NodePort for the ArgoCD server HTTPS port."
  type        = number
  default     = 30081
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

# --- Crossplane AWS provider ---

variable "crossplane_aws_provider_version" {
  description = "Version tag for the Upbound AWS family/service provider packages (xpkg.upbound.io/upbound/provider-aws-*)."
  type        = string
  default     = "v2.9.0"
}

variable "crossplane_aws_service_providers" {
  description = "List of Upbound AWS service provider packages to install (short names, e.g. \"ec2\", \"rds\"). The provider-family package is always installed as their dependency."
  type        = list(string)
  default     = ["ec2", "rds", "s3"]
}

variable "crossplane_aws_providerconfig_name" {
  description = "Name of the Crossplane AWS ProviderConfig."
  type        = string
  default     = "default"
}

variable "crossplane_aws_iam_user_name" {
  description = "Name of the IAM user whose access key is given to the Crossplane AWS ProviderConfig."
  type        = string
  default     = "crossplane-aws-guild"
}
