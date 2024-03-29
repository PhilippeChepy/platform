# Terraform

Terraform configurations:
- depend on the `locals.tf` file, located at the root of this repository,
- creates some secret files in the `artifacts` subdirectory

The whole infrastructure is provisioned by applying 5 configurations, one after another:
- `terraform-base`: for the Vault infrastructure
- `terraform-base-configuration`: for the Vault configuration and required Exoscale IAM keys
- `terraform-kubernetes`: for the Etcd and Kubernetes infrastructure, and argocd bootstrapping

Additionally, integration with Cloudflare is set by applying an additional configuration:
- `terraform-cloudflare`: (optional, only if using Cloudflare) deploys external-DNS and lets-encrypt integration using DNS01 issuer

## Base components and secret management with Vault (terraform-base)

This configuration creates all required elements for other parts of the platform:
- a CA certificate and the related private key
- an operator security group (allows to access SSH, and clients of services: `Hashicorp Vault`, `Etcd`, and `Kubernetes` API server)
- an SSH keypair
- a Vault cluster, which needs to be initialized and unsealed

### Overview

![Terraform base](../assets/terraform-base%402x.png)

### Module: vault

The Vault module allows the provisioning of a Vault cluster:
- An anti-affinity group to ensure each cluster member goes to distinct hypervisors on the Exoscale side
- Two security groups: one for cluster members, another one for clients to be allowed to access the cluster
- A Network Load Balancer (NLB) as a final endpoint to reach the Vault cluster, and other critical infrastructure components
- An instance pool to ease template updates (doing a rolling update of each instance after having updated the instance pools template). By default, this instance pool size is 3, allowing to have a failing member.

### Post-provisioning tasks

- **TLS bootstrapping**. Before allowing any cluster operations, Vault needs a valid TLS certificate to start its API.
- **Cluster init and unseal operations**. Once provisioned, Vault must be [initialized](https://www.vaultproject.io/docs/commands/operator/init). This task should be done in only one instance. After initialization, each cluster member should be [unsealed](https://www.vaultproject.io/docs/commands/operator/unseal).

Both previous tasks can be performed using the `vault-cluster-bootstrap.yaml` Ansible playbook:

```bash
ansible-playbook -i artifacts/vault-inventory.yml playbooks/vault-cluster-bootstrap.yaml
```

## Base configuration (terraform-base-configuration)

This configuration creates the most required secrets and PKI secret engines in Vault, using the [Terraform Vault provider](https://registry.terraform.io/providers/hashicorp/vault/latest/docs).

It sets a PKI secret engine for Vault: the ICA path for this PKI is `pki/platform/vault`. This ICA is signed by the platform Root CA. 

### Secrets engines

| Engine Path                                | Role / Data                   | Policy                                         | Description                                     |
|--------------------------------------------|-------------------------------|------------------------------------------------|-------------------------------------------------|
| /iam/exoscale                              | etcd-instance-pool            | etcd                                           | IAM key for etcd cluster automatic setup
| /iam/exoscale                              | cloud-controller-manager      | cloud-controller-manager                       | IAM key for kubelet CSR validation
| /iam/exoscale                              | cluster-autoscaler            |                                                | **Not yet in use**
| /pki/root                                  |                               |                                                | **used by `terraform-kubernetes`** to signs /pki/platform/vault
| /pki/platform/vault                        | server                        | vault                                          | server certificate
| /pki/platform/kubernetes/etcd              | server                        | etcd                                           | server+client certificate
| /pki/platform/kubernetes/etcd              | apiserver                     | control-plane (api-server)                     | client certificate
| /pki/platform/kubernetes/control-plane     | apiserver                     | control-plane (api-server)                     | server certificate
| /pki/platform/kubernetes/control-plane     | controller-manager            | control-plane (controller-manager)             | client certificate
| /pki/platform/kubernetes/control-plane     | scheduler                     | control-plane (scheduler)                      | client certificate
| /pki/platform/kubernetes/control-plane     | cloud-controller-manager      | cloud-controller-manager                       | client certificate
| /pki/platform/kubernetes/control-plane     | konnectivity                  | control-plane (apiserver-network-proxy)        | client certificate, konnectivity
| /pki/platform/kubernetes/control-plane     | konnectivity-server-cluster   | control-plane (apiserver-network-proxy)        | server certificate, konnectivity
| /pki/platform/kubernetes/control-plane     | konnectivity-agent            |                                                | server certificate, **Not yet in use**
| /pki/platform/kubernetes/aggregation-layer | metrics-server                | metrics-server                                 | server certificate
| /pki/platform/kubernetes/aggregation-layer | apiserver                     | control-plane (api-server)                     | client certificate
| /pki/platform/kubernetes/kubelet           | apiserver                     | control-plane (api-server)                     | client certificate
| /pki/platform/kubernetes/client            | operator-admin                |                                                | client certificate, **used by `terraform-kubernetes`**
| /kv/platform/kubernetes                    | kubelet-pki                   | control-plane (controller-manager)             | secret: kubelet CA and private key
| /kv/platform/kubernetes                    | service-account               | control-plane (api-server, controller-manager) | secret: signing/verification key
| /kv/platform/kubernetes                    | secret-encryption             | control-plane (api-server)                     | secret: kubernetes secret encryption at rest
| /kv/platform/kubernetes                    | kubelet-bootstrap-token       |                                                | secret: token for kubelet bootstrapping process, **set in instances `user_data` by `terraform-kubernetes`**

### Authentication

| Auth engine    | Role                     | Authentication based on                                 |
|----------------|--------------------------|---------------------------------------------------------|
| /auth/exoscale | vault-server             | Security group: ${platform-name}-vault-server           |
| /auth/exoscale | etcd-server              | Security group: ${platform-name}-etcd-server            |
| /auth/exoscale | kubernetes-control-plane | Security group: ${platform-name}-kubernetes-controllers |

## Post-provisioning tasks

Once resources from this sub-directory are created, you can start vault-agent (`systemctl start vault-agent`) on each vault instance. Vault agent will authenticate using the [Exoscale Vault authentication plugin](https://github.com/exoscale/vault-plugin-auth-exoscale). It will automatically renew Vault server certificates and reload the server service.

This task can be performed using the `vault-cluster-tls-agent.yaml` Ansible playbook:

```bash
ansible-playbook -i artifacts/vault-inventory.yml playbooks/vault-cluster-tls-agent.yaml
```

## Etcd & Kubernetes cluster (terraform-kubernetes)

This configuration creates an etcd cluster, a kubernetes control plane (2 nodes by default), and kubelet instance-pools.
It also waits for the cluster to be available, and deploy required manifests to bootstrap a minimal ArgoCD deployment;
ArgoCD will then take care of deploying other base deployments

![Terraform Kubernetes](../assets/terraform-kubernetes%402x.png)

### Additional authentication setup

| Auth engine                           | Role                          | Authentication based on                                                      |
|---------------------------------------|-------------------------------|------------------------------------------------------------------------------|
| /auth/kubernetes/cert-manager         | certificate-metrics-server    | Service account/token: kube-system/cert-manager-metrics-server (-token)      |
| /auth/kubernetes/external-secrets     | cert-manager-dns01-cloudflare | Service account/token: cert-manager/<ingress>-cert-manager-dns01-cloudflare  |
| /auth/kubernetes/external-secrets     | external-dns-cloudflare       | Service account/token: <ingress-namespace>/<ingress>-external-dns-cloudflare |

## Provisioning instructions

See [the initial provisioning runbook for provisioning instructions](../runbooks/Initial-Provisioning.md#provision-the-infrastructure-using-terraform).
