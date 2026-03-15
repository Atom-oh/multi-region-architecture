variable "global_cluster_identifier" {
  description = "The global cluster identifier for the Aurora PostgreSQL global database"
  type        = string
  default     = "multi-region-mall-aurora"
}

variable "database_name" {
  description = "The name of the default database to create in the global cluster"
  type        = string
  default     = "mall"
}
