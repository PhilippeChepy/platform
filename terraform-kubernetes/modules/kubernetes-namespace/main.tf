resource "null_resource" "namespace" {
  triggers = {
    apply_command  = "kubectl create namespace ${var.namespace}"
    delete_command = "kubectl delete namespace ${var.namespace} --ignore-not-found=true"
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