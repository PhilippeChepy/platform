locals {
  domains = [
    for _, ingress in local.platform_components.kubernetes.ingresses : try(ingress.domain, null)
    if try(ingress.domain, null) != null
  ]

  api_keys = toset(concat([
    for name, ingress in local.platform_components.kubernetes.ingresses : [
      for _, deployment in try(ingress.deployments, []) : "${name}-${deployment}"
      if try(local.platform_components.kubernetes.deployments.ingress[deployment].provider, "") == "cloudflare" && try(local.platform_components.kubernetes.deployments.ingress[deployment].credentials, false)
    ]
  ]...))
}

data "cloudflare_api_token_permission_groups" "all" {
}

data "cloudflare_zone" "zone" {
  for_each = toset(local.domains)
  name     = each.key
}


resource "cloudflare_record" "base_services" {
  for_each = merge([
    for domain in toset(local.domains) : {
      for service in toset(["vault", "etcd", "kube-api"]) : "${service}.${local.platform_domain}" => {
        domain = domain
        name   = service
      }
    }
    if trimsuffix(".${local.platform_domain}", ".${domain}") != ".${local.platform_domain}"
  ]...)

  zone_id = data.cloudflare_zone.zone[each.value.domain].id
  name    = "${each.value.name}.${local.platform_domain}."
  value   = local.kubernetes.control_plane_ip_address
  type    = "A"
  ttl     = 120
}

resource "cloudflare_api_token" "api_key" {
  for_each = local.api_keys

  name = local.platform_name

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.permissions["DNS Write"],
      data.cloudflare_api_token_permission_groups.all.permissions["Zone Read"],
    ]
    resources = {
      for zone in local.domains :
      "com.cloudflare.api.account.zone.${data.cloudflare_zone.zone[zone].zone_id}" => "*"
    }
  }
}

resource "vault_mount" "secret_cloudflare" {
  path        = "kv/platform/cloudflare"
  description = "Cloudflare Secrets"

  type = "kv"
}

resource "vault_generic_secret" "external_dns_api_key" {
  depends_on = [vault_mount.secret_cloudflare]
  for_each   = local.api_keys
  path       = "${vault_mount.secret_cloudflare.path}/${each.key}"

  data_json = jsonencode({
    api-key = cloudflare_api_token.api_key[each.key].value
  })
}

resource "vault_policy" "policy" {
  for_each = local.api_keys

  name = "platform-deployment-ingress-${each.key}"

  policy = <<EOT
path "${vault_mount.secret_cloudflare.path}/${each.key}" {
  capabilities = ["read"]
}
EOT
}
