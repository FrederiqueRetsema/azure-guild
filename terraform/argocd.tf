resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.argocd_namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  wait = true

  values = [
    yamlencode({
      configs = {
        cm = {
          # Some resources have no runtime health condition, so ArgoCD leaves
          # them Progressing forever (shown as a spinner under each Composition
          # in the tree). Treat them as Healthy so the app can reach a fully
          # synced/healthy state.
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
          "resource.customizations.health.apiextensions.crossplane.io_CompositionRevision" = <<-EOT
            hs = {}
            hs.status = "Healthy"
            hs.message = "CompositionRevision is an immutable snapshot; treated as Healthy"
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
