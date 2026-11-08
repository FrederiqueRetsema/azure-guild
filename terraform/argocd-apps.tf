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
        path           = "guild-app"
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

resource "kubernetes_manifest" "crossplane_composition" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "crossplane-composition"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.github_repo_url
        targetRevision = var.github_repo_revision
        path           = "crossplane-composition"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.argocd_app_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
