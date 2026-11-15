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
      finalizers = [
        "resources-finalizer.argocd.argoproj.io",
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.github_repo_url
        targetRevision = var.github_repo_revision
        path           = var.crossplane_managed_resource_path
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


resource "kubernetes_manifest" "portable_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "portable-app"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io",
      ]
    }
    spec = {
      project = "default"
      # Shared XRDs/functions plus the AWS compositions and composites.
      sources = [
        {
          repoURL        = var.github_repo_url
          targetRevision = var.github_repo_revision
          path           = "portable-app/common"
        },
        {
          repoURL        = var.github_repo_url
          targetRevision = var.github_repo_revision
          path           = "portable-app/aws"
        },
      ]
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "portable-app"
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
