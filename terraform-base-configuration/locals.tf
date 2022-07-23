locals {
  iam_role = {
    vault_iam = {
      tags = ["iam"]
    }
    etcd_instance_pool = {
      operations = [
        "list-instance-pools",
        "get-anti-affinity-group",
        "get-security-group",
        "get-instance-pool",
        "get-elastic-ip",
        "get-instance",
        "get-instance-type",
        "get-template",
        "list-instances",
      ]
    }
    vault_instance_pool = {
      operations = [
        "list-instance-pools",
        "get-anti-affinity-group",
        "get-security-group",
        "get-instance-pool",
        "get-elastic-ip",
        "get-instance",
        "get-instance-type",
        "get-template",
        "list-instances",
      ]
    }
    cloud_controller_manager = {
      operations = [
        "add-service-to-load-balancer",
        "create-load-balancer",
        "delete-load-balancer",
        "delete-load-balancer-service",
        "get-instance",
        "get-instance-type",
        "get-load-balancer",
        "get-load-balancer-service",
        "get-operation",
        "list-instances",
        "list-load-balancers",
        "list-zones",
        "reset-load-balancer-field",
        "reset-load-balancer-service-field",
        "update-load-balancer",
        "update-load-balancer-service",
      ]
    }
    cluster_autoscaler = {
      operations = [
        "evict-instance-pool-members",
        "get-instance-pool",
        "get-instance",
        "get-operation",
        "get-quota",
        "scale-instance-pool",
      ]
    },
    vault_backup = {
      operations = [
        "list-sos-bucket",
        "create-sos-bucket",
        "put-sos-object",
        "get-sos-object",
        "delete-sos-object"
      ]
      resources = ["sos/bucket:${local.rclone.vault.bucket}"]
    }
    etcd_backup = {
      operations = [
        "list-sos-bucket",
        "create-sos-bucket",
        "put-sos-object",
        "get-sos-object",
        "delete-sos-object"
      ]
      resources = ["sos/bucket:${local.rclone.etcd.bucket}"]
    }
  }
}