resource "kubernetes_manifest" "crossplane_provider_family_aws" {
  manifest = {
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata = {
      name = "provider-family-aws"
    }
    spec = {
      package = "xpkg.upbound.io/upbound/provider-family-aws:${var.crossplane_aws_provider_version}"
    }
  }

  depends_on = [helm_release.crossplane]
}

resource "kubernetes_manifest" "crossplane_provider_aws_service" {
  for_each = toset(var.crossplane_aws_service_providers)

  manifest = {
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata = {
      name = "provider-aws-${each.value}"
    }
    spec = {
      package = "xpkg.upbound.io/upbound/provider-aws-${each.value}:${var.crossplane_aws_provider_version}"
    }
  }

  depends_on = [kubernetes_manifest.crossplane_provider_family_aws]
}

# --- Credentials for the Crossplane AWS provider ---
# Crossplane runs inside the cluster, so it gets its own IAM user with just
# enough permissions for the service providers installed above.

resource "aws_iam_user" "crossplane" {
  name = var.crossplane_aws_iam_user_name

  # Allow destroy even if keys were created outside Terraform.
  force_destroy = true
}

resource "aws_iam_user_policy_attachment" "crossplane" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
  ])

  user       = aws_iam_user.crossplane.name
  policy_arn = each.value
}

resource "aws_iam_access_key" "crossplane" {
  user = aws_iam_user.crossplane.name
}

resource "kubernetes_secret" "crossplane_aws_creds" {
  metadata {
    name      = "aws-secret"
    namespace = var.crossplane_namespace
  }

  data = {
    creds = <<-EOT
      [default]
      aws_access_key_id = ${aws_iam_access_key.crossplane.id}
      aws_secret_access_key = ${aws_iam_access_key.crossplane.secret}
    EOT
  }

  type = "Opaque"

  depends_on = [helm_release.crossplane]
}

resource "kubernetes_manifest" "crossplane_aws_providerconfig" {
  manifest = {
    apiVersion = "aws.upbound.io/v1beta1"
    kind       = "ProviderConfig"
    metadata = {
      name = var.crossplane_aws_providerconfig_name
    }
    spec = {
      credentials = {
        source = "Secret"
        secretRef = {
          namespace = var.crossplane_namespace
          name      = kubernetes_secret.crossplane_aws_creds.metadata[0].name
          key       = "creds"
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.crossplane_provider_family_aws,
    kubernetes_secret.crossplane_aws_creds,
    aws_iam_user_policy_attachment.crossplane,
    kubernetes_manifest.crossplane_managed_resource,
    kubernetes_manifest.portable_app,
  ]
}
