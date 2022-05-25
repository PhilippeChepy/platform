output "root_ca_certificate_pem" {
  value = module.ca_certificate.certificate_pem
}

output "root_ca_private_key_pem" {
  value     = module.ca_certificate.private_key_pem
  sensitive = true
}

output "ssh_public_key_openssh" {
  value = tls_private_key.management_key.public_key_openssh
}

output "ssh_private_key_openssh" {
  value     = tls_private_key.management_key.private_key_pem
  sensitive = true
}
