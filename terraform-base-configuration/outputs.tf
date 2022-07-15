output "user_initial_password" {
  sensitive = true
  value = {
    for user, _ in local.platform_authentication["provider"] == "vault" ? local.platform_authentication["users"] : {} :
    user => random_password.user_initial_password[user].result
  }
}