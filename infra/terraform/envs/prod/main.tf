# prod environment. Own folder = own state, so a plan here can't touch the other env.

terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

provider "kubernetes" {
  config_path    = pathexpand("~/.kube/hello-platform.kubeconfig")
  config_context = "kind-hello-platform"
}

module "podinfo" {
  source      = "../../modules/app-namespace"
  environment = "prod"

  # only through the ingress, no LoadBalancer/NodePort services
  quota = {
    # room for maxReplicas=10 plus rollout surge
    "requests.cpu"           = "4"
    "requests.memory"        = "4Gi"
    "limits.memory"          = "6Gi"
    "pods"                   = "20"
    "services.loadbalancers" = "0"
    "services.nodeports"     = "0"
  }
}
