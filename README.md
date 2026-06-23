# tf-elasticache-common

Generic ElastiCache building block. Creates one or more Valkey/Redis replication groups
with their supporting resources (subnet group, parameter group, security group, optional
slow-log delivery to CloudWatch). Follows the same conventions as `tf-ecs-common`.

## Features

- **VPC auto-discovery** — no VPC/subnet IDs needed; discovered by standard `Account` /
  `Organization` / `ManagedBy` tags.
- **Parameter group ownership** — module always owns the parameter group, so callers can
  add custom parameters without rebuilding the cluster.
- **Security group per cluster** — module creates and manages one SG; additional
  pre-existing SGs can be attached via `security_group_ids`.
- **TLS + AUTH** — `transit_encryption_enabled` (default `true`) and optional `auth_token`.
- **Slow-log delivery** — opt-in per cluster; module creates the CloudWatch log group.
- **Consistent naming** — `{region_short}-{organization}-{project}-elasticache-{cluster_key}`.

> **40-character limit**: ElastiCache replication group IDs may not exceed 40 characters.
> The module enforces this via a `precondition`. With the standard naming scheme,
> a cluster_key of up to ~9 characters fits comfortably for typical project names.

## Example — Valkey cluster for the strike project

```hcl
module "elasticache" {
  source = "git::https://github.com/Scrypt-Swiss/tf-elasticache-common.git?ref=main"

  region_short = var.region_short
  organization = var.organization
  project      = var.project
  account_name = var.account_name

  clusters = {
    # Creates: euc1-scrypt-strike-elasticache-cache
    cache = {
      engine     = "valkey"
      engine_version = "8.0"
      node_type  = "cache.t4g.small"

      num_cache_clusters         = 2
      automatic_failover_enabled = true
      multi_az_enabled           = true

      at_rest_encryption_enabled = true
      transit_encryption_enabled = true
      transit_encryption_mode    = "required"
      # Fetch from Secrets Manager before passing in:
      # auth_token = data.aws_secretsmanager_secret_version.cache_token.secret_string

      slow_log_enabled = true

      security_group_ingress_rules = {
        # Allow the ECS backend cluster SG to reach Redis on port 6379.
        "backend-ecs" = {
          protocol                     = "tcp"
          from_port                    = 6379
          to_port                      = 6379
          referenced_security_group_id = module.ecs.security_group_ids["backend/api"]
        }
      }
    }
  }

  tags = var.tags
}
```

## Example — Single-node development cluster (no HA, no auth)

```hcl
clusters = {
  cache = {
    engine     = "valkey"
    engine_version = "8.0"
    node_type  = "cache.t4g.micro"

    at_rest_encryption_enabled = true
    transit_encryption_enabled = false
  }
}
```

## Resources created

| Resource | Name pattern |
|---|---|
| `aws_elasticache_replication_group` | `{region_short}-{org}-{project}-elasticache-{key}` |
| `aws_elasticache_subnet_group` | `…-elasticache-{key}-subnet` |
| `aws_elasticache_parameter_group` | `…-elasticache-{key}-params` |
| `aws_security_group` | `…-elasticache-{key}-sg` |
| `aws_cloudwatch_log_group` (slow logs) | `/elasticache/…-elasticache-{key}/slow-logs` |

## Adding new features

Add optional fields to the cluster object in `variables.tf` with `optional(…, default)`.
Gate the new resource or block with a filtered local:

```hcl
clusters_with_engine_logs = {
  for ck, c in var.clusters : ck => c if c.engine_log_enabled
}
```

Then create the resource with `for_each = local.clusters_with_engine_logs`.
