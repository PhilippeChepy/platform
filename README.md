# TL;DR

This repository implements various OS templates, for use in Exoscale cloud.
These templates are mostly used to implement a custom Kubernetes distribution.

Related repositories:
- [Terraform ETCD @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-etcd): contains an `etcd` HA cluster implementation @ Exoscale Cloud
- [Terraform Kubernetes @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubernetes): contains Kubernetes control plane implementation @ Exoscale Cloud
- [Terraform Kubelet Pool @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubelet-pool): contains a Kubernetes node pool implementation @ Exoscale Cloud
- [Example cluster](https://github.com/PhilippeChepy/kubernetes-exoscale-demo): an example of a deployment involving previously mentioned modules

# Templates

- etcd.pkr.hcl (Etcd 3.5.1):
    - Settings must be set in `/etc/default/etcd` when deploying.
- kube-controlplane.pkr.hcl (Kubernetes 1.23.1 control plane):
    - Lots of certificates must be set
    - Used by [Terraform Kubernetes @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubernetes)
- kube-node.pkr.hcl (Kubernetes 1.23.1 node):
    - TLS is bootstraped with a token
    - Used by [Terraform Kubelet Pool @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubelet-pool)

# TODO

- Hashicorp Vault
