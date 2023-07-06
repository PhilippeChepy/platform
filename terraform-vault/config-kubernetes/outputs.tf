output "control_plane_ca_pem" {
  value = vault_pki_secret_backend_root_cert.pki_control_plane.certificate
}

output "kubelet_ca_pem" {
  value = tls_self_signed_cert.kubelet_ca.cert_pem
}

output "operator_kubeconfig" {
  value = <<EOT
apiVersion: v1
clusters:
  - cluster:
      certificate-authority-data: ${base64encode(vault_pki_secret_backend_root_cert.pki_control_plane.certificate)}
      server: https://${var.internal_nlb.ip_address}:6443
    name: ${var.specs.infrastructure.name}
contexts:
  - context:
      cluster: ${var.specs.infrastructure.name}
      user: default
    name: ${var.specs.infrastructure.name}
current-context: ${var.specs.infrastructure.name}
kind: Config
preferences: {}
users:
  - name: default
    user:
      client-certificate-data: ${base64encode(vault_pki_secret_backend_cert.operator.certificate)}
      client-key-data: ${base64encode(vault_pki_secret_backend_cert.operator.private_key)}
EOT
}
