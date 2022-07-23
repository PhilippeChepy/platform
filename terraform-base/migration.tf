moved {
  from = module.ca_certificate.tls_self_signed_cert.root_ca
  to   = tls_self_signed_cert.root_ca
}

moved {
  from = module.ca_certificate.tls_private_key.root_ca
  to   = tls_private_key.root_ca
}
