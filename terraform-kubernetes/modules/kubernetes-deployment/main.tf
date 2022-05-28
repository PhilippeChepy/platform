
locals {
  deployment_variables_regex = "\\$(${join("|", keys(var.deployment_variables))})\\$"
  rendered_manifest = var.templated ? join("\n", [
    for line in split("\n", file(var.deployment_manifest_file)) :
    format(replace(line, "/${local.deployment_variables_regex}/", "%s"), [
      for value in flatten(regexall(local.deployment_variables_regex, line)) : lookup(var.deployment_variables, value)
    ]...)
  ]) : ""

  apply_untemplated = <<-EOT
try_iter=0
until [ "$try_iter" -ge 5 ]
do
  kubectl apply --namespace=${var.deployment_namespace} --filename=${var.deployment_manifest_file} && break
  sleep 5
done
EOT

  apply_templated = <<-EOT
try_iter=0
until [ "$try_iter" -ge 5 ]
do
   cat <<'EOF' | kubectl apply --namespace=${var.deployment_namespace} --filename=- && break
${sensitive(local.rendered_manifest)}
EOF
   try_iter=$((try_iter+1)) 
   sleep 5
done
EOT

  delete_untemplated = <<-EOT
  kubectl delete --namespace=${var.deployment_namespace} --ignore-not-found=true --filename=${var.deployment_manifest_file}
EOT

  delete_templated = <<-EOT
cat <<'EOF' | kubectl delete --namespace=${var.deployment_namespace} --ignore-not-found=true --filename=-
${sensitive(local.rendered_manifest)}
EOF
EOT
}

resource "null_resource" "deployment" {
  triggers = {
    apply_command = var.templated == false ? local.apply_untemplated : local.apply_templated
    delete_command  = var.templated == false ? local.delete_untemplated : local.delete_templated
    kubeconfig_path = var.kubeconfig_path
  }

  provisioner "local-exec" {
    when    = create
    command = self.triggers.apply_command
    environment = {
      KUBECONFIG = "../artifacts/admin.kubeconfig"
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers.delete_command
    environment = {
      KUBECONFIG = "../artifacts/admin.kubeconfig"
    }
  }
}

module "service_account_token" {
  for_each   = var.service_account_tokens
  source     = "./modules/kubernetes-serviceaccount-token"
  depends_on = [null_resource.deployment]

  kubeconfig_path = var.kubeconfig_path

  name            = each.key
  namespace       = var.deployment_namespace
  service_account = each.value["service_account"]
}

resource "null_resource" "readiness_check" {
  for_each   = { for check in var.readiness_checks : "${check["kind"]}/${try(check["name"], join("|", try(check["labels"], [])))}" => check }
  depends_on = [null_resource.deployment, module.service_account_token]

  triggers = {
    apply_command   = null_resource.deployment.triggers.apply_command
    kubeconfig_path = var.kubeconfig_path

    # common
    mode      = coalesce(each.value["mode"], "rollout")
    namespace = var.deployment_namespace
    kind      = each.value["kind"]
    timeout   = coalesce(each.value["timeout"], "10m")
    name      = coalesce(each.value["mode"], "rollout") == "rollout" ? try(each.value["name"], null) : null
    condition = coalesce(each.value["mode"], "rollout") == "wait" ? coalesce(each.value["condition"], "ready") : null
    labels    = coalesce(each.value["mode"], "rollout") == "wait" ? join(",", coalesce(each.value["labels"], [])) : null
  }

  provisioner "local-exec" {
    when    = create
    command = "while ! kubectl -n ${self.triggers.namespace} ${self.triggers.mode == "rollout" ? "rollout status ${self.triggers.kind}/${self.triggers.name}" : "wait --for=condition=${self.triggers.condition} ${self.triggers.kind} -l ${self.triggers.labels}"} --timeout=${self.triggers.timeout}; do echo \"Waiting for deployment\"; sleep 5; done"

    environment = {
      KUBECONFIG = "../artifacts/admin.kubeconfig"
    }
  }
}