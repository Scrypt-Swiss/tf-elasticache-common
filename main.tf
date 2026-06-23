locals {
  # Replication group IDs composed as:
  #   "<region_short>-<organization>-<project>-elasticache-<cluster_key>"
  # e.g. "euc1-scrypt-strike-elasticache-cache"
  # AWS limit: 40 characters. A precondition on the resource enforces this.
  cluster_names = {
    for ck, c in var.clusters : ck => "${var.region_short}-${var.organization}-${var.project}-elasticache-${ck}"
  }

  # Discovered workload subnet IDs.
  workload_subnet_ids = data.aws_subnets.workload.ids

  # Derived parameter group family: "<engine><major_version>" (e.g. "valkey8", "redis7").
  parameter_group_families = {
    for ck, c in var.clusters : ck => (
      c.parameter_group_family != null
      ? c.parameter_group_family
      : "${c.engine}${split(".", c.engine_version)[0]}"
    )
  }

  # Flatten ingress rules from all clusters into a single map keyed
  # "<cluster_key>/<rule_key>" for resource iteration.
  ingress_rules_flat = merge([
    for ck, c in var.clusters : {
      for rk, r in c.security_group_ingress_rules : "${ck}/${rk}" => merge(r, {
        cluster_key = ck
      })
    }
  ]...)

  # Clusters that have slow-log delivery enabled.
  clusters_with_slow_logs = {
    for ck, c in var.clusters : ck => c if c.slow_log_enabled
  }

  # Standard tags identifying the VPC created by the networking stack.
  vpc_discovery_tags = {
    Account      = var.account_name
    Organization = var.organization
    ManagedBy    = "terraform"
  }
}

# ─── VPC / subnet discovery ──────────────────────────────────────────────────

data "aws_vpc" "main" {
  tags = local.vpc_discovery_tags
}

data "aws_subnets" "workload" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Name"
    values = [var.workload_subnet_name_pattern]
  }
}

# ─── Subnet group ────────────────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "this" {
  for_each = var.clusters

  name        = "${local.cluster_names[each.key]}-subnet"
  subnet_ids  = local.workload_subnet_ids
  description = "Subnet group for ${local.cluster_names[each.key]}"

  tags = merge(var.tags, { Name = "${local.cluster_names[each.key]}-subnet" })
}

# ─── Parameter group ─────────────────────────────────────────────────────────

resource "aws_elasticache_parameter_group" "this" {
  for_each = var.clusters

  name   = "${local.cluster_names[each.key]}-params"
  family = local.parameter_group_families[each.key]

  dynamic "parameter" {
    for_each = each.value.parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = merge(var.tags, { Name = "${local.cluster_names[each.key]}-params" })

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Security group ───────────────────────────────────────────────────────────

resource "aws_security_group" "this" {
  for_each = var.clusters

  name        = "${local.cluster_names[each.key]}-sg"
  description = "Security group for ElastiCache cluster ${local.cluster_names[each.key]}"
  vpc_id      = data.aws_vpc.main.id

  tags = merge(var.tags, { Name = "${local.cluster_names[each.key]}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules_flat

  security_group_id            = aws_security_group.this[each.value.cluster_key].id
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.referenced_security_group_id
  description                  = each.value.description

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.clusters

  security_group_id = aws_security_group.this[each.key].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = var.tags
}

# ─── CloudWatch slow-log groups ──────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "slow_logs" {
  for_each = local.clusters_with_slow_logs

  name              = "/elasticache/${local.cluster_names[each.key]}/slow-logs"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "/elasticache/${local.cluster_names[each.key]}/slow-logs" })
}

# ─── ElastiCache replication group ───────────────────────────────────────────

resource "aws_elasticache_replication_group" "this" {
  for_each = var.clusters

  replication_group_id = local.cluster_names[each.key]
  description          = "ElastiCache ${each.value.engine} cluster for ${var.project} (${each.key})"

  engine         = each.value.engine
  engine_version = each.value.engine_version
  node_type      = each.value.node_type

  num_cache_clusters = each.value.num_cache_clusters

  parameter_group_name = aws_elasticache_parameter_group.this[each.key].name
  subnet_group_name    = aws_elasticache_subnet_group.this[each.key].name
  security_group_ids = concat(
    [aws_security_group.this[each.key].id],
    each.value.security_group_ids,
  )

  automatic_failover_enabled = each.value.automatic_failover_enabled
  multi_az_enabled           = each.value.multi_az_enabled

  at_rest_encryption_enabled = each.value.at_rest_encryption_enabled
  transit_encryption_enabled = each.value.transit_encryption_enabled
  transit_encryption_mode    = each.value.transit_encryption_mode
  auth_token                 = each.value.auth_token
  auth_token_update_strategy = each.value.auth_token_update_strategy

  maintenance_window       = each.value.maintenance_window
  snapshot_retention_limit = each.value.snapshot_retention_limit
  snapshot_window          = each.value.snapshot_window

  dynamic "log_delivery_configuration" {
    for_each = each.value.slow_log_enabled ? [1] : []
    content {
      destination      = aws_cloudwatch_log_group.slow_logs[each.key].name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "slow-log"
    }
  }

  tags = merge(var.tags, { Name = local.cluster_names[each.key] })

  lifecycle {
    precondition {
      condition     = length(local.cluster_names[each.key]) <= 40
      error_message = "Composed replication group ID '${local.cluster_names[each.key]}' exceeds the 40-character ElastiCache limit. Shorten region_short, organization, project, or the cluster key."
    }
    # Prevent destruction of a live cache cluster. Remove this safeguard only
    # when explicitly decommissioning the cluster.
    prevent_destroy = false
  }
}
