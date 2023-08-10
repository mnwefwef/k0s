provider "aws" {
  default_tags {
    tags = {
      "ostests.k0sproject.io/instance"             = local.resource_name_prefix
      "ostests.k0sproject.io/os"                   = var.os
      "ostests.k0sproject.io/k0s-network-provider" = var.k0s_network_provider
    }
  }
}

resource "random_pet" "resource_name_prefix" {
  count = var.resource_name_prefix == null ? 1 : 0
}

locals {
  resource_name_prefix = coalesce(var.resource_name_prefix, random_pet.resource_name_prefix.*.id...)
  cache_dir            = pathexpand(coalesce(var.cache_dir, "~/.cache/k0s-ostests"))
  podCIDR              = "10.244.0.0/16"
}

module "os" {
  source = "./modules/os"

  os                       = var.os
  additional_ingress_cidrs = [local.podCIDR]
}

module "infra" {
  source = "./modules/infra"

  resource_name_prefix     = local.resource_name_prefix
  os                       = module.os.os
  additional_ingress_cidrs = [local.podCIDR]
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = module.infra.ssh_private_key
  filename        = "${local.cache_dir}/aws-${local.resource_name_prefix}-ssh-private-key.pem"
  file_permission = "0400"
}

module "k0sctl" {
  source = "./modules/k0sctl"

  k0sctl_executable_path = var.k0sctl_executable_path
  k0s_executable_path    = var.k0s_executable_path
  k0s_version            = var.k0s_version

  k0s_config_spec = {
    network = {
      provider = var.k0s_network_provider
      podCIDR  = local.podCIDR
      nodeLocalLoadBalancing = {
        enabled = true
      }
    }
  }

  hosts                    = try(module.infra.nodes, []) # the try allows destruction even if infra provisioning failed
  ssh_private_key_filename = local_sensitive_file.ssh_private_key.filename
}
