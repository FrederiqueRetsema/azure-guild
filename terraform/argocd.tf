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

# ArgoCD Application that tracks the configurable GitHub repository.
# Defined as a raw manifest so it does not require a dedicated ArgoCD provider.
resource "kubernetes_manifest" "guild_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.argocd_app_name
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.github_repo_url
        targetRevision = var.github_repo_revision
        path           = var.github_repo_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.argocd_app_namespace
      }
      syncPolicy = {
        # automated = {
        #   prune    = true
        #   selfHeal = true
        # }
        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
