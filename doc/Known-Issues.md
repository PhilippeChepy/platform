# Known issues (and workarounds)

## Expired Kubernetes admin client configuration

```
 Error: External Program Execution Failed
│ 
│   with module.deployment_core["vault-agent-injector"].module.service_account_token["vault-server"].data.external.token,
│   on modules/kubernetes-deployment/modules/kubernetes-serviceaccount-token/main.tf line 49, in data "external" "token":
│   49:   program    = ["kubectl", "--kubeconfig=../artifacts/admin.kubeconfig", "--namespace=${var.namespace}", "get", "secret", var.name, "-o", "jsonpath={.data}"]
│ 
│ The data source received an unexpected error while attempting to execute the program.
│ 
│ Program: /usr/local/bin/kubectl
│ Error Message: error: You must be logged in to the server (Unauthorized)
│ 
│ State: exit status 1
```

To connect to the Kubernetes cluster, the Terraform definition uses a kubeconfig file with a quite short TTL (4d by default).
This kubeconfig file is created using Vault, and is not automatically renewed when expired.

### Solution

You can force Terraform to build a new kubeconfig file that contains a renewed TLS client certificate:

```bash
# From the terraform-kubernetes directory
terraform state rm vault_pki_secret_backend_cert.operator
terraform apply -target vault_pki_secret_backend_cert.operator -target local_file.kubeconfig
```
