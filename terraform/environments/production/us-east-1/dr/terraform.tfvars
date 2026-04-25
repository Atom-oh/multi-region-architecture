environment                 = "production"
region                      = "us-east-1"
docdb_global_cluster_id     = "production-docdb-global"
docdb_target_cluster_id     = "production-docdb-global-us-west-2"
elasticache_target_region   = "us-west-2"
elasticache_target_group_id = "production-elasticache-us-west-2"
notification_email          = "ops@example.com"
enable_auto_failover        = false

tags = {
  Project = "multi-region-mall"
  Team    = "platform"
}
