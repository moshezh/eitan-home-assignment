# everything the app gets from the platform in one environment
# a namespace with guardrails and a CI identity that can only deploy into it
# The app itself is deployed by Helm.

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

variable "app" {
  type    = string
  default = "podinfo"
}

variable "environment" {
  type = string
}

variable "quota" {
  type = map(string)
}

locals {
  ns = "${var.app}-${var.environment}"
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = local.ns
    labels = {
      environment                          = var.environment
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
}

resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "quota"
    namespace = local.ns
  }
  spec {
    hard = var.quota
  }
  depends_on = [kubernetes_namespace_v1.this]
}

# Deny everything, then allow DNS. The chart opens the one port the app needs.
resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny"
    namespace = local.ns
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_network_policy_v1" "allow_dns" {
  metadata {
    name      = "allow-dns"
    namespace = local.ns
  }
  spec {
    pod_selector {}
    policy_types = ["Egress"]
    egress {
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "kube-system" }
        }
        pod_selector {
          match_labels = { "k8s-app" = "kube-dns" }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
  depends_on = [kubernetes_namespace_v1.this]
}

# CI deployer: can manage the app objects in this namespace only.
# No RBAC rights, so it can't give itself more.
resource "kubernetes_service_account_v1" "deployer" {
  metadata {
    name      = "ci-deployer"
    namespace = local.ns
  }
  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_role_v1" "deployer" {
  metadata {
    name      = "helm-deployer"
    namespace = local.ns
  }
  rule {
    # helm keeps release history in secrets
    api_groups = ["", "apps", "networking.k8s.io", "autoscaling", "policy"]
    resources  = ["services", "secrets", "deployments", "ingresses", "networkpolicies", "horizontalpodautoscalers", "poddisruptionbudgets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["", "apps"]
    resources  = ["pods", "pods/log", "events", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }
  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_role_binding_v1" "deployer" {
  metadata {
    name      = "helm-deployer"
    namespace = local.ns
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.deployer.metadata[0].name
    namespace = local.ns
  }
}

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}
