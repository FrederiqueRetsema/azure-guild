resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.argocd_namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  wait = true

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
