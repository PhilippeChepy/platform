locals {
  secret_manifest = <<-EOT
---
apiVersion: v1
kind: Secret
metadata:
  name: ${var.name}
  namespace: ${var.namespace}
  annotations:
    kubernetes.io/service-account.name: ${var.service_account}
type: kubernetes.io/service-account-token
EOT
}

resource "null_resource" "token_secret" {
  triggers = {
    apply_command = <<-EOT
cat <<'EOF' | kubectl apply --namespace=${var.namespace} --filename=-
${local.secret_manifest}
EOF
EOT

    delete_command = <<-EOT
cat <<'EOF' | kubectl delete --namespace=${var.namespace} --ignore-not-found=true --filename=-
${local.secret_manifest}
EOF
EOT
  }

  provisioner "local-exec" {
    when    = create
    command = sensitive(self.triggers.apply_command)
    environment = {
      KUBECONFIG = "../artifacts/admin.kubeconfig"
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = sensitive(self.triggers.delete_command)
    environment = {
      KUBECONFIG = "../artifacts/admin.kubeconfig"
    }
  }
}

data "external" "token" {
  depends_on = [null_resource.token_secret]
  program    = ["kubectl", "--kubeconfig=../artifacts/admin.kubeconfig", "--namespace=${var.namespace}", "get", "secret", var.name, "-o", "jsonpath={.data}"]
}


