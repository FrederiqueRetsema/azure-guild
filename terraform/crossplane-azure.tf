# Crossplane Azure provider scaffolding.
#
# This installs the Upbound Azure family provider plus a configurable set of
# service providers (resources, network, storage, ...), and wires in Azure
# service-principal credentials through a Secret + ProviderConfig so Crossplane
# can manage Azure resources via the Kubernetes API.
#
# Everything here is gated on install_crossplane_azure_provider (and the core
# install_crossplane). The credentials Secret and ProviderConfig are only
# created when crossplane_azure_credentials_json is non-empty.

# The Azure family provider. Service providers depend on this package; we also
# install it explicitly so its ProviderConfig CRDs (azure.upbound.io) appear.
resource "kubernetes_manifest" "crossplane_provider_family_azure" {
  manifest = {
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata = {
      name = "provider-family-azure"
    }
    spec = {
      package = "xpkg.upbound.io/upbound/provider-family-azure:${var.crossplane_azure_provider_version}"
    }
  }

  depends_on = [helm_release.crossplane]
}

resource "kubernetes_manifest" "crossplane_provider_azure_service" {
  for_each = toset(var.crossplane_azure_service_providers)

  manifest = {
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata = {
      name = "provider-azure-${each.value}"
    }
    spec = {
      package = "xpkg.upbound.io/upbound/provider-azure-${each.value}:${var.crossplane_azure_provider_version}"
    }
  }

  depends_on = [kubernetes_manifest.crossplane_provider_family_azure]
}

# Secret holding the Azure service-principal credentials JSON.
resource "kubernetes_secret" "crossplane_azure_creds" {
  metadata {
    name      = "azure-secret"
    namespace = var.crossplane_namespace
  }

  data = {
    creds = var.crossplane_azure_credentials_json
  }

  type = "Opaque"

  depends_on = [helm_release.crossplane]
}

resource "kubernetes_manifest" "crossplane_azure_providerconfig" {
  manifest = {
    apiVersion = "azure.upbound.io/v1beta1"
    kind       = "ProviderConfig"
    metadata = {
      name = var.crossplane_azure_providerconfig_name
    }
    spec = {
      credentials = {
        source = "Secret"
        secretRef = {
          namespace = var.crossplane_namespace
          name      = kubernetes_secret.crossplane_azure_creds.metadata[0].name
          key       = "creds"
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.crossplane_provider_family_azure,
    kubernetes_secret.crossplane_azure_creds,
  ]
}
