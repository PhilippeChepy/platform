output "token" {
  value = base64decode(data.external.token.result["token"])
}