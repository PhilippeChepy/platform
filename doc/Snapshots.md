# On-demand snapshots

It can be useful to create snapshots of Etcd or Vault on-demand, for instance
just before upgrading a cluster.

There is a runbook for each of these services to build snapshots and retrieve them
on the operator workstation.

Commands from this document are to be run from the root of this repository.

# Vault Snapshots

```bash
ansible-playbook -i artifacts/inventory.yml ansible-playbooks/vault-dump-snapshot.yaml
# 【output】
# 
# ... truncated ...
# paas-staging-vault-addab-gdfgz : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
# paas-staging-vault-addab-jmvoo : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
# paas-staging-vault-addab-xzsiu : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

After running this runbook, the snapshot is available on your machine in the `artifacts` subdirectory:

```bash
ls -lah artifacts/latest-vault.snapshot
# 【output】
# -rw-r--r--  1 philippe  staff    20M 16 jul 13:37 artifacts/latest-vault.snapshot
```


# Etcd Snapshots

```bash
ansible-playbook -i artifacts/etcd-inventory.yml ansible-playbooks/etcd-dump-snapshot.yaml
# 【output】
#
# ... truncated ...
# paas-staging-etcd-326fe-dyrni : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
# paas-staging-etcd-326fe-hvbmi : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
# paas-staging-etcd-326fe-kfluy : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

After running this runbook, the snapshot is available on your machine in the `artifacts` subdirectory:

```bash
ls -lah artifacts/latest-etcd.snapshot
# 【output】
# -rw-r--r--  1 philippe  staff   5,8M 16 jul 13:35 artifacts/latest-etcd.snapshot
```