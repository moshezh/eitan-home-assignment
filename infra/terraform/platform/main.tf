# Cluster add-ons: ingress controller and metrics-server (needed by the HPA autoscaling).
# Separate root from "terraform\cluster" because the helm provider needs a cluster that already exists.

terraform {
  required_version = ">= 1.6"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/hello-platform.kubeconfig"
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = "kind-hello-platform"
  }
}

# Installs Traefik
# Traefik and not ingress-nginx: ingress-nginx was retired in March 2026.
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "41.6.1"
  namespace        = "traefik"
  create_namespace = true

  values = [yamlencode({
    ingressClass = {
      enabled        = true
      isDefaultClass = true
    }
    nodeSelector = { "ingress-ready" = "true" }
    tolerations = [{
      key      = "node-role.kubernetes.io/control-plane"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
    ports = {
      web       = { hostPort = 80 }
      websecure = { hostPort = 443 }
    }
    # no cloud LB locally, traffic comes in through the hostPorts
    service = { spec = { type = "ClusterIP" } }
  })]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  namespace  = "kube-system"

  # kind kubelets use self-signed certs - local only
  values = [yamlencode({ args = ["--kubelet-insecure-tls"] })]
}
