# Etcd Disaster recovery

This procedure is based on the official [Etcd disaster recovery procedure](https://etcd.io/docs/v3.5/op-guide/recovery/) from etcd.io documentation.

## The "automated" method

This method is based on an Ansible playbook.

1. Place the snapshot to restore in the `artifact` subdirectory, under the name `latest-etcd.snapshot`.
2. Run the restoration playbook:
    ```bash
    ansible-playbook -i artifacts/kubernetes-inventory.yml ansible-playbooks/etcd-snapshot-restore.yaml
    # 【output】
    # ... truncated ...
    # paas-staging-etcd-96640-adchh : ok=10   changed=8    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
    # paas-staging-etcd-96640-wjxyn : ok=10   changed=8    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
    # paas-staging-etcd-96640-zdhxs : ok=10   changed=8    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
    #
    ```
3. Check your Kubernetes workload status
