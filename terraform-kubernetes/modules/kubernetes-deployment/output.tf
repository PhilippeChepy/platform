output "serviceaccount_tokens" {
  value = {
    for token_name, _ in var.service_account_tokens :
    (token_name) => module.service_account_token[token_name].token
  }
}