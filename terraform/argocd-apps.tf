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
        # Retry so the composite resource converges once the XRD's CRD is
        # registered, even if the first sync pass loses the race.
        retry = {
          limit = 5
          backoff = {
            duration    = "10s"
            factor      = 2
            maxDuration = "2m"
          }
        }
        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }

  depends_on = [helm_release.argocd, helm_release.crossplane]
}

resource "kubernetes_manifest" "crossplane_managed_resource" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "crossplane-managed-resource"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.github_repo_url
        targetRevision = var.github_repo_revision
        path           = "crossplane-managed-resource"
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
        retry = {
          limit = 5
          backoff = {
            duration    = "10s"
            factor      = 2
            maxDuration = "2m"
          }
        }
        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }

  depends_on = [helm_release.argocd, helm_release.crossplane]
}


resource "kubernetes_manifest" "portable_database" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "portable-database"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.github_repo_url
        targetRevision = var.github_repo_revision
        path           = "portable-database"
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
        # Retry so the composite resources converge once the XRD's CRD is
        # registered, even if the first sync pass loses the race.
        retry = {
          limit = 5
          backoff = {
            duration    = "10s"
            factor      = 2
            maxDuration = "2m"
          }
        }
        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }

  depends_on = [helm_release.argocd, helm_release.crossplane]
}
