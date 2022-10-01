# Platform infrastructure

This repository implements a minimal platform hosted in the Exoscale public cloud.

This platform is based on:
- Hashicorp Vault for secret management
- Kubernetes for workloads orchestration
- ArgoCD for deployments (optional)

Multi-tenancy can be achieved using:
- Namespaces along resources quota and limit
- Network Policies

### Global overview

![Global overview](doc/assets/Platform%402x.png)

### Tools & configuration

- [Packer templates](./doc/configuration/packer.md)
- [Terraform provisioning & configuration](./doc/configuration/terraform.md)

### Runbooks

- [Full provisioning instructions](./doc/runbooks/Initial-Provisioning.md)
- [Building a fresh Vault snapshot & retrieving it locally](./doc/runbooks/Snapshots.md#vault-snapshots)
- [Building a fresh Etcd snapshot & retrieving it locally](./doc/runbooks/Snapshots.md#etcd-snapshots)
- [Upgrading the Vault cluster](./doc/runbooks/Upgrade-Vault-Instances.md)
- [Upgrading the Etcd cluster](./doc/runbooks/Upgrade-Kubernetes-Datastore.md)
- [Upgrading the Kubernetes control plane](./doc/runbooks/Upgrade-Kubernetes-ControlPlane.md)
- [Upgrading the Kubernetes Nodes instance pools](./doc/runbooks/Upgrade-Kubernetes-Node-InstancePool.md)
- [Disaster Recovery: Vault](./doc/runbooks/DisasterRecovery-Vault.md)
- [Disaster Recovery: Etcd](./doc/runbooks/DisasterRecovery-Etcd.md)
- [Destroying the whole infrastructure](./doc/runbooks/Destroy-Everything.md)

### Additional documentation

- Official [Vault disaster recovery procedure](https://learn.hashicorp.com/tutorials/vault/sop-restore#single-vault-cluster) from Hashicorp Learn
- Official [Etcd disaster recovery procedure](https://etcd.io/docs/v3.5/op-guide/recovery/) from etcd.io documentation

### Known issues (and workarounds)

- [Expired local Kubernetes admin client configuration](./doc/misc/Known-Issues.md#expired-kubernetes-admin-client-configuration)
