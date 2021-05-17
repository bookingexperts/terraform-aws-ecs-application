terraform {
  experiments = [module_variable_optional_attrs]
}

# Application settings
variable "name" { type = string }
variable "env" { type = string }
variable "environment" { type = map(string) }
variable "subdomain" { default = "" }
variable "log_retention" { default = 30 }
variable "legacy_container_names" { default = false }
variable "storage_base_path" { default = "/mnt/efs" }
variable "workload_type" { default = "testing" }

# Task specific settings
variable "web" {
  type = object({
    cpu                  = number
    memory               = number
    count                = optional(number)
    deregistration_delay = number

    deployment_minimum_healthy_percent = number
    deployment_maximum_percent         = number

    health_check = map(any)
    auto_scaling = optional(map(any))
  })
}

variable "worker" {
  type = object({
    cpu    = number
    memory = number
    count  = optional(number)

    deployment_minimum_healthy_percent = number
    deployment_maximum_percent         = number

    auto_scaling = optional(map(any))
  })
}

variable "cloudfront" {
  default = {}
}

variable "s3" {
  default = {}
}

variable "redis" {
  type = map(map(any))
  default = {}
}

variable "rds" {
  default = {}
}

# Passed resources
variable "ecs_cluster" { type = object({ arn = string, name = string }) }
variable "vpc" { type = object({ id = string }) }
variable "ses_iam_policy" { type = object({ arn = string }) }
variable "ecr_repository" { type = object({ repository_url = string }) }
variable "route53_zones" {
  type = object({
    internal = object({ zone_id = string, name = string })
    external = object({ zone_id = string, name = string })
  })
}
variable "load_balancers" {
  type = object({
    listener = object({ arn = string })
    internal = object({ arn = string, security_groups = list(string), subnets = list(string) })
    external = object({ dns_name = string, zone_id = string })
  })
}

# Misc.
data "aws_region" "current" {}
locals {
  name            = "${var.name}-${var.env}"
  tld             = substr(var.route53_zones.external.name, 0, length(var.route53_zones.external.name))
  subdomain       = coalesce(var.subdomain, var.env)
  hostname        = "${local.subdomain}.${local.tld}"
  wildcard        = "*.${local.hostname}"
  cdn_host        = "cdn.${local.hostname}"
  container_names = var.legacy_container_names ? { web = "puma", worker = "sidekiq", console = "deploy" } : { web = "web", worker = "worker", console = "deploy" }
  auto_scaling    = merge(var.web.auto_scaling, { min_web_capacity = coalesce(var.web.count, 1),  min_worker_capacity = coalesce(var.worker.count, 1) })
}

provider "aws" {}
provider "aws" { alias = "cdn" }
