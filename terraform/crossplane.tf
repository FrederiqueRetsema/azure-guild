resource "helm_release" "crossplane" {
  name             = "crossplane"
  namespace        = var.crossplane_namespace
  create_namespace = true

  repository = "https://charts.crossplane.io/stable"
  chart      = "crossplane"
  version    = var.crossplane_chart_version

  # Wait for the Crossplane controllers and CRDs to be ready.
  wait = true

  depends_on = [azurerm_kubernetes_cluster.this]
}
