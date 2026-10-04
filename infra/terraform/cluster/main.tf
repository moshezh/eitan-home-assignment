# kind cluster (1 control plane + 2 workers) and a local registry that is replacing Artifactory.
# On EKS this root is the only thing that gets replaced.

terraform {
  required_version = ">= 1.6"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/hello-platform.kubeconfig"
}

locals {
  registry_name = "kind-registry"
  registry_port = 5001
  certs_dir = abspath("${path.root}/.generated/containerd-certs.d")
}

resource "local_file" "registry_hosts" {
  filename = "${local.certs_dir}/localhost:${local.registry_port}/hosts.toml"
  content  = "[host.\"http://${local.registry_name}:5000\"]\n"
}

resource "kind_cluster" "this" {
  name            = "hello-platform"
  node_image      = "kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5"
  kubeconfig_path = pathexpand(var.kubeconfig_path)
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node { # 1 control-plane node
      role = "control-plane"

      # traefik runs here and binds 80/443 -> laptop 8080/8443
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      extra_port_mappings {
        container_port = 80
        host_port      = 8080
        listen_address = "127.0.0.1"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 8443
        listen_address = "127.0.0.1"
      }
      extra_mounts {
        host_path      = local.certs_dir
        container_path = "/etc/containerd/certs.d"
        read_only      = true
      }
    }

    dynamic "node" { # and 2 worker nodes
      for_each = range(2)
      content {
        role = "worker"
        extra_mounts {
          host_path      = local.certs_dir
          container_path = "/etc/containerd/certs.d"
          read_only      = true
        }
      }
    }
  }

  depends_on = [local_file.registry_hosts]
}

resource "docker_image" "registry" { #pulls the kind image
  name         = "registry:3"
  keep_locally = true
}

resource "docker_container" "registry" { #create and run a local kind container
  name    = local.registry_name
  image   = docker_image.registry.image_id
  restart = "always"

  # no auth on this registry, so only bind to loopback
  ports {
    internal = 5000
    external = local.registry_port
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name = "kind"
  }

  depends_on = [kind_cluster.this]
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}
