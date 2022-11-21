locals {
  admin_user_emails = [for user in local.platform_authentication.users : user.email if contains(user.groups, "administrator")]

  bootstrap_deployment_variable = {
    argocd_core_project_name                            = "platform-core"
    argocd_deployment_argocd_path                       = "kubernetes/core/argocd"
    argocd_deployment_argocd_repository                 = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_argocd_revision                   = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_argocd_self_heal                  = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_deployment_cert_manager_path                 = "kubernetes/core/cert-manager"
    argocd_deployment_cert_manager_repository           = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_cert_manager_revision             = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_cert_manager_self_heal            = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_deployment_cilium_path                       = "kubernetes/core/cilium"
    argocd_deployment_cilium_repository                 = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_cilium_revision                   = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_cilium_self_heal                  = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_deployment_coredns_path                      = "kubernetes/core/coredns"
    argocd_deployment_coredns_repository                = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_coredns_revision                  = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_coredns_self_heal                 = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_deployment_dex_path                          = "kubernetes/core/dex"
    argocd_deployment_dex_repository                    = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_dex_revision                      = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_dex_self_heal                     = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_deployment_konnectivity_agent_path           = "kubernetes/core/konnectivity-agent"
    argocd_deployment_konnectivity_agent_repository     = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_konnectivity_agent_revision       = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_konnectivity_agent_self_heal      = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_deployment_kyverno_path                      = "kubernetes/core/kyverno"
    argocd_deployment_kyverno_repository                = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_kyverno_revision                  = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_kyverno_self_heal                 = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_deployment_metrics_server_path               = "kubernetes/core/metrics-server"
    argocd_deployment_metrics_server_repository         = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_metrics_server_revision           = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_metrics_server_self_heal          = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_deployment_network_policies_path             = "kubernetes/core/network-policies"
    argocd_deployment_network_policies_repository       = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_network_policies_revision         = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_network_policies_self_heal        = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_deployment_reloader_path                     = "kubernetes/core/reloader"
    argocd_deployment_reloader_repository               = local.platform_components.kubernetes.deployments.core.repository
    argocd_deployment_reloader_revision                 = local.platform_components.kubernetes.deployments.core.revision
    argocd_deployment_reloader_self_heal                = local.platform_components.kubernetes.deployments.core.self_heal
    argocd_platform_argocd_hostname                     = "cd.${local.platform_domain}"
    argocd_platform_argocd_ingress_class_name           = "ingress-internal-nginx"
    argocd_platform_argocd_oidc_client_secret           = data.vault_generic_secret.oidc_client_secret["argocd"].data["client-secret"]
    argocd_platform_argocd_policy                       = <<-EOT
%{~for user in local.admin_user_emails~}
  g, ${user}, role:admin
%{~endfor~}
EOT
    argocd_platform_dex_cacert                          = data.local_file.root_ca_certificate_pem.content
    argocd_platform_dex_hostname                        = "dex.${local.platform_domain}"
    argocd_platform_dex_ingress_class_name              = "ingress-internal-nginx"
    argocd_platform_dex_oidc_client_id                  = local.platform_authentication["provider"] == "vault" ? data.vault_generic_secret.oidc_client_secret["dex"].data["client_id"] : null
    argocd_platform_dex_oidc_client_secret              = local.platform_authentication["provider"] == "vault" ? data.vault_generic_secret.oidc_client_secret["dex"].data["client_secret"] : null
    argocd_platform_dex_oidc_issuer                     = "https://vault.${local.platform_domain}:8200/v1/identity/oidc/provider/default"
    argocd_platform_dex_public_ip                       = local.kubernetes.ingress["internal"].ip_address
    argocd_platform_domain                              = local.platform_domain
    argocd_platform_kubernetes_aggregation_layer_cacert = data.vault_generic_secret.kubernetes["aggregation-layer-ca"].data["ca_chain"]
    argocd_platform_kubernetes_apiserver_address        = local.kubernetes.control_plane_ip_address
    argocd_platform_kubernetes_cluster_dns_service_ipv4 = local.platform_components.kubernetes.dns_service_ipv4
    argocd_platform_kubernetes_cluster_dns_service_ipv6 = local.platform_components.kubernetes.dns_service_ipv6
    argocd_platform_kubernetes_cluster_domain           = local.platform_components.kubernetes.cluster_domain
    argocd_platform_kubernetes_cluster_pod_cidr_ipv4    = local.platform_components.kubernetes.pod_cidr_ipv4
    argocd_platform_kubernetes_cluster_pod_cidr_ipv6    = local.platform_components.kubernetes.pod_cidr_ipv6
    argocd_platform_kubernetes_kubelet_cacert           = data.vault_generic_secret.kubernetes["kubelet-ca"].data["ca_chain"]
    argocd_platform_kubernetes_proxyserver_address0     = local.kubernetes.control_plane_instance_ip_address[0]
    argocd_platform_kubernetes_proxyserver_address1     = local.kubernetes.control_plane_instance_ip_address[1]
    argocd_platform_vault_aggregation_layer_pki_path    = local.pki.pki_sign_aggregation_layer
    argocd_platform_vault_base_url                      = local.vault.url
    argocd_platform_vault_cacert                        = data.local_file.root_ca_certificate_pem.content
    argocd_platform_vault_core_pki_sign_path            = local.pki.pki_sign_deployment["core"]
    argocd_platform_vault_public_ip                     = local.vault.ip_address
    argocd_root_application_core_path                   = "kubernetes/core/root-application"
    argocd_root_application_core_repository             = local.platform_components.kubernetes.deployments.core.repository
    argocd_root_application_core_revision               = local.platform_components.kubernetes.deployments.core.revision
    argocd_root_application_core_ssh_deploy_key         = ""

    argocd_ingress = {
      for ingress_name, ingress in local.platform_components.kubernetes.ingresses : ingress_name => {
        deployment_cert_manager_dns01_cloudflare_path       = "kubernetes/ingress/cert-manager-dns01-cloudflare",
        deployment_cert_manager_dns01_cloudflare_repository = local.platform_components.kubernetes.deployments.ingress.repository,
        deployment_cert_manager_dns01_cloudflare_revision   = local.platform_components.kubernetes.deployments.ingress.revision,
        deployment_cert_manager_dns01_cloudflare_self_heal  = local.platform_components.kubernetes.deployments.ingress.self_heal,
        deployment_cert_manager_selfsigned_path             = "kubernetes/ingress/cert-manager-selfsigned",
        deployment_cert_manager_selfsigned_repository       = local.platform_components.kubernetes.deployments.ingress.repository,
        deployment_cert_manager_selfsigned_revision         = local.platform_components.kubernetes.deployments.ingress.revision,
        deployment_cert_manager_selfsigned_self_heal        = local.platform_components.kubernetes.deployments.ingress.self_heal,
        deployment_cert_mmanager_http01_path                = "kubernetes/ingress/cert-manager-http01",
        deployment_cert_mmanager_http01_repository          = local.platform_components.kubernetes.deployments.ingress.repository,
        deployment_cert_mmanager_http01_revision            = local.platform_components.kubernetes.deployments.ingress.revision,
        deployment_cert_mmanager_http01_self_heal           = local.platform_components.kubernetes.deployments.ingress.self_heal,
        deployment_external_dns_cloudflare_path             = "kubernetes/ingress/external-dns-cloudflare",
        deployment_external_dns_cloudflare_repository       = local.platform_components.kubernetes.deployments.ingress.repository,
        deployment_external_dns_cloudflare_revision         = local.platform_components.kubernetes.deployments.ingress.revision,
        deployment_external_dns_cloudflare_self_heal        = local.platform_components.kubernetes.deployments.ingress.self_heal,
        deployment_nginx_ingress_controller_path            = "kubernetes/ingress/nginx-ingress-controller",
        deployment_nginx_ingress_controller_repository      = local.platform_components.kubernetes.deployments.ingress.repository,
        deployment_nginx_ingress_controller_revision        = local.platform_components.kubernetes.deployments.ingress.revision,
        deployment_nginx_ingress_controller_self_heal       = local.platform_components.kubernetes.deployments.ingress.self_heal,
        name                                                = "ingress-${ingress_name}",
        platform_domain                                     = local.platform_domain,
        platform_ingress_cloudflare_api_token               = ingress.integration == "cloudflare" ? data.vault_generic_secret.cloudflare[ingress_name].data["api-key"] : null,
        platform_ingress_domain                             = try(ingress.domain, ""),
        platform_ingress_label_name                         = "${local.platform_domain}/ingress",
        platform_ingress_label_value                        = ingress_name,
        platform_ingress_loadbalancer_ip                    = local.kubernetes.ingress[ingress_name].ip_address,
        platform_ingress_taint_name                         = "${local.platform_domain}/ingress",
        platform_ingress_taint_value                        = ingress_name,
        root_application_path                               = "kubernetes/ingress/root-application",
        root_application_repository                         = local.platform_components.kubernetes.deployments.ingress.repository,
        root_application_revision                           = local.platform_components.kubernetes.deployments.ingress.revision,
        ssh_deploy_key                                      = "",
      }
    }
  }
}