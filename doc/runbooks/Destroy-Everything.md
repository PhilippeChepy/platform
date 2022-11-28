# Destroy everything

WARNING: Following this guide will completely remove your infrastructure from
your Exoscale account. There is no way to rollback (even if you have backups,
and you rebuild the infrastructure, you will loose your ingress pool public IP
addresses).

## Destroying the Kubernetes cluster

1. Edit the `terraform-kubernetes/main.tf` file: Search for the `exoscale_nlb.ingress` resource definition:
```terraform
resource "exoscale_nlb" "ingress" {
  for_each = local.platform_components.kubernetes.ingresses

  zone        = local.platform_zone
  name        = "${local.platform_name}-ingress-${each.key}"
  description = "Ingress load balancer (${each.key})"

  lifecycle {
    prevent_destroy = true
  }
}
```
2. Comment the `lifecycle` block:
```terraform
resource "exoscale_nlb" "ingress" {
  for_each = local.platform_components.kubernetes.ingresses

  zone        = local.platform_zone
  name        = "${local.platform_name}-ingress-${each.key}"
  description = "Ingress load balancer (${each.key})"

  # lifecycle {
  #   prevent_destroy = true
  # }
}
```
3. Then save the file with the commented block, and destroy the Kubernetes infrastructure: from the `terraform-kubernetes` sub-directory, run `terraform destroy`.
4. Undo the change made at step 1.
5. If applicable, fom the `terraform-cloudflare` sub-directory, run `terraform destroy`.

## Destroying the Base configuration

1. From the `terraform-base-configuration` sub-directory, run `terraform destroy`.

## Destroying the Base infrastructure

1. Remove everything from the `etcd` and `vault` snapshost buckets (using the CLI, s3cmd, Web UI, etc.).
2. From the `terraform-base` sub-directory, run `terraform destroy`.

## Manual tasks

1. Delete templates from your Exoscale account:
    - `Etcd x.y.z`
    - `Kubernetes x.y control plane`
    - `Kubernetes x.y node`
    - `Vault x.y.z`
2. Cleanup artifacts (files in the `artifacts` sub-directory):
    - `*.json`
    - `*.txt`
