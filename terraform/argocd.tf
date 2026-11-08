resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.argocd_namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  wait = true

  # Register custom health checks so ArgoCD does not block forever on
  # Crossplane config objects that never report a runtime health condition.
  #
  # A (Cluster)ProviderConfig is a passive object: Crossplane only writes
  # status.users to it and never a Ready/Healthy condition. Because it sits in
  # sync-wave 0, ArgoCD waits for it to become Healthy before applying wave 1
  # (the Compositions) and wave 2 (the MySQL2 composites) -- a deadlock that
  # leaves the app Progressing indefinitely. Treating these objects as Healthy
  # immediately lets the sync proceed.
  values = [
    yamlencode({
      configs = {
        cm = {
          "resource.customizations.health.azure.m.upbound.io_ClusterProviderConfig" = <<-EOT
            hs = {}
            hs.status = "Healthy"
            hs.message = "ClusterProviderConfig has no runtime health; treated as Healthy"
            return hs
          EOT
          "resource.customizations.health.azure.upbound.io_ProviderConfig"          = <<-EOT
            hs = {}
            hs.status = "Healthy"
            hs.message = "ProviderConfig has no runtime health; treated as Healthy"
            return hs
          EOT
        }
      }
    })
  ]

  set = [
    {
      name  = "server.service.type"
      value = "NodePort"
    },
    {
      name  = "server.service.nodePortHttp"
      value = tostring(var.argocd_nodeport_http)
    },
    {
      name  = "server.service.nodePortHttps"
      value = tostring(var.argocd_nodeport_https)
    },
  ]

  depends_on = [azurerm_kubernetes_cluster.this]
}
