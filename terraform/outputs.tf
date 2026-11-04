output "nodeport_access_command" {
  description = "Command to list node public IPs for reaching the NodePort service once nodes have public IPs."
  value = "kubectl get nodes -o jsonpath=\"{range .items[*]}{.status.addresses[?(@.type=='ExternalIP')].address}{'\\n'}{end}\" then browse http://<node-ip>:${var.nodeport}"
}

output "argocd_nodeport_access" {
  description = "How to reach the ArgoCD UI over the NodePort once nodes have public IPs."
  value = "Browse https://<node-ip>:${var.argocd_nodeport_https} (or http://<node-ip>:${var.argocd_nodeport_http}). Get a node IP with: kubectl get nodes -o wide"
}

output "crossplane_namespace" {
  description = "Namespace where Crossplane is installed"
  value       = var.crossplane_namespace
}

output "crossplane_azure_status" {
  description = "Status of the Crossplane Azure provider and credentials wiring."
  value = (
    !nonsensitive(trimspace(var.crossplane_azure_credentials_json) != "") ?
    "Azure provider installed (packages: provider-family-azure, ${join(", ", formatlist("provider-azure-%s", var.crossplane_azure_service_providers))}); no credentials provided, create the Secret + ProviderConfig manually" :
    "Azure provider installed with ProviderConfig '${var.crossplane_azure_providerconfig_name}' wired to secret 'azure-secret'"
  )
}
