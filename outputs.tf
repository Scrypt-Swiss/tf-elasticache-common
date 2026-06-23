# Cluster-keyed outputs (key = cluster_key, e.g. "cache").

output "replication_group_ids" {
  description = "Map of cluster key to ElastiCache replication group ID."
  value       = { for k, rg in aws_elasticache_replication_group.this : k => rg.id }
}

output "replication_group_arns" {
  description = "Map of cluster key to ElastiCache replication group ARN."
  value       = { for k, rg in aws_elasticache_replication_group.this : k => rg.arn }
}

output "primary_endpoint_addresses" {
  description = "Map of cluster key to the primary endpoint address (connect here for writes)."
  value       = { for k, rg in aws_elasticache_replication_group.this : k => rg.primary_endpoint_address }
}

output "reader_endpoint_addresses" {
  description = "Map of cluster key to the reader endpoint address (load-balanced across replicas)."
  value       = { for k, rg in aws_elasticache_replication_group.this : k => rg.reader_endpoint_address }
}

output "port" {
  description = "Map of cluster key to the port the cluster accepts connections on."
  value       = { for k, rg in aws_elasticache_replication_group.this : k => rg.port }
}

output "security_group_ids" {
  description = "Map of cluster key to the module-created security group ID."
  value       = { for k, sg in aws_security_group.this : k => sg.id }
}

output "subnet_group_names" {
  description = "Map of cluster key to the ElastiCache subnet group name."
  value       = { for k, sg in aws_elasticache_subnet_group.this : k => sg.name }
}

output "parameter_group_names" {
  description = "Map of cluster key to the ElastiCache parameter group name."
  value       = { for k, pg in aws_elasticache_parameter_group.this : k => pg.name }
}

output "slow_log_group_names" {
  description = "Map of cluster key to CloudWatch slow-log log group name (only clusters with slow_log_enabled)."
  value       = { for k, lg in aws_cloudwatch_log_group.slow_logs : k => lg.name }
}
