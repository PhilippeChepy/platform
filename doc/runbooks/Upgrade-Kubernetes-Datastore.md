# Kubernetes Datastore (aka Etcd) upgrade procedure

**IMPORTANT** First, you need to perform a backup of your Etcd cluster, this would help you easily rollback in case of disaster.
Once your backup is made and stored in a safe location, you can proceed with the next steps.

1. Build the new Etcd template:
  - move to the `packer` directory
  - run packer: `packer build -var-file vars.hcl exoscale-etcd.pkr.hcl`
  - grab the template ID from the output: `--> exoscale.base: Etcd 3.5.4 @ de-fra-1 (23dc1f3e-e381-4a4f-bd4a-ed976bbb59bc)`
2. Update the Etcd instance-pool:
  - Update the value for `platform_components.kubernetes.templates.etcd` in your `locals.tf` file with the template ID from step 1. Keep the older
  value for the cleanup step
  - move to the `terraform-kubernetes` directory
  - run `terraform apply`, this should update the instance-pool template ID
3. With `exo` CLI, or by other means, get the list of current Etcd instances. These instances are using the old template:
    ```bash
    exo compute instance list |grep etcd
    # 【output】
    # | 87aae3e3-bb76-4b47-afcd-3e5d23035420 | paas-staging-etcd-326fe-cvuje             | de-fra-1 | standard.micro | 89.145.160.150 | running |
    # | 4cf2e809-d5e8-4815-ac7c-9ce4dc23e7f7 | paas-staging-etcd-326fe-ypwwc             | de-fra-1 | standard.micro | 89.145.161.228 | running |
    # | d4ec20e2-11e2-4e69-96a3-7cccae28b6a0 | paas-staging-etcd-326fe-qezxh             | de-fra-1 | standard.micro | 194.182.169.37 | running |
    ```
4. Connect to one of the instances to monitor cluster state
    - Move to the `artifacts` directory
    - Connect to the instance (`ssh -i id_ed25519 ubuntu@89.145.160.150`)
    - Sudo to the etcd user (`sudo -iu etcd`)
    - Then `watch etcdctl  member list`
    - Keep this terminal open
5. With `exo` CLI, or by other means, delete an instance belonging to the list found in step 3.
    ```bash
    exo compute instance delete paas-staging-etcd-326fe-ypwwc
    # 【output】
    # [+] Are you sure you want to delete instance "paas-staging-etcd-326fe-ypwwc"? [yN]: y
    #  ✔ Deleting instance "paas-staging-etcd-326fe-ypwwc"... 1m42s
    ```
6. A new instance will be automatically created to replace the one you just deleted:
    - Wait for the new instance to be running
    - Check the cluster status from the termnal you opened in step 4; you need to ensure that (this usually takes ~2mn):
        - The instance you have deleted is not anymore in the cluster
        - A new instance joined the cluster
    - Check the new cluster member's raft data are up to date.
7. Repeat operations from step 5 (or 4) for other cluster members found in step 3.
8. Delete the older template (value before the step 2 update) as it's not used anymore:
    ```bash
    exo compute template delete -z de-fra-1 bb0d1a71-0601-4f0c-9dc5-51bfde57a890
    # 【output】
    # [+] Are you sure you want to delete template bb0d1a71-0601-4f0c-9dc5-51bfde57a890 ("Etcd 3.5.4")? [yN]: y
    #  ✔ Deleting template bb0d1a71-0601-4f0c-9dc5-51bfde57a890... 3s
    ```
