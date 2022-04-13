# TL;DR

This repository implements various OS templates, for use in Exoscale cloud.
These templates are mostly used to implement a custom Kubernetes distribution.

Related repositories:
- [Terraform ETCD @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-etcd): contains an `etcd` HA cluster implementation @ Exoscale Cloud
- [Terraform Kubernetes @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubernetes): contains Kubernetes control plane implementation @ Exoscale Cloud
- [Terraform Kubelet Pool @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubelet-pool): contains a Kubernetes node pool implementation @ Exoscale Cloud
- [Example cluster](https://github.com/PhilippeChepy/kubernetes-exoscale-demo): an example of a deployment involving previously mentioned modules

# Templates

- `etcd.pkr.hcl` (Etcd 3.5.3):
    - Settings must be set in `/etc/default/etcd` when deploying.
    - For use with an Hashicorp Vault cluster for TLS management, or manual provisioning
    - Used by [Terraform Kubernetes @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubernetes)
- `kube-controlplane.pkr.hcl` (Kubernetes 1.23.5 control plane):
    - For use with an Hashicorp Vault cluster for TLS management, or manual provisioning
    - Used by [Terraform Kubernetes @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubernetes)
- `kube-node.pkr.hcl` (Kubernetes 1.23.5 node):
    - TLS is bootstraped with a token
    - Used by [Terraform Kubelet Pool @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubelet-pool)
- `vault.pkr.hcl` (Vault 1.10.0)
    - Used by [Terraform Vault @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-vault)

# Build instructions

- Create a `.vars.hcl` file (template: `.vars.hcl.example`), set your API keys/secrets inside.
- Initialize packer if you don't have the Exoscale Packer plugin (`packer init <packer-file>`)
- Build the template (`packer build -var-file .vars.hcl <packer-file>`)
