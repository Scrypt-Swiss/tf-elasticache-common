# ─── Naming ──────────────────────────────────────────────────────────────────
# Replication group names are composed in-module as:
#   "<region_short>-<organization>-<project>-elasticache-<cluster_key>"
# e.g. "euc1-scrypt-strike-elasticache-cache"
# Note: ElastiCache replication group IDs are capped at 40 characters.

variable "region_short" {
  type        = string
  description = "Short region code used in resource names (e.g. \"euc1\")."
}

variable "organization" {
  type        = string
  description = "Organization slug used in resource names (e.g. \"scrypt\")."
}

variable "project" {
  type        = string
  description = "Project slug used in resource names (e.g. \"strike\")."
}

# ─── VPC / subnet discovery ──────────────────────────────────────────────────
# The module discovers the VPC and subnets itself (no networking-stack dependency
# and no caller-supplied IDs). The VPC is matched on the org's standard tags,
# composed from account_name + organization.

variable "account_name" {
  type        = string
  description = "Composed account name (e.g. \"wl-dev\"). Used with organization to discover the VPC."
}

variable "workload_subnet_name_pattern" {
  type        = string
  description = "tag:Name pattern matching the subnets ElastiCache clusters are placed in."
  default     = "*workload*"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days for slow-log log groups."
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value accepted by CloudWatch Logs (0 = never expire)."
  }
}

# ─── Clusters ────────────────────────────────────────────────────────────────
# Map of ElastiCache replication groups to create. The key becomes the
# cluster_key in the composed name and keys all per-cluster resources.

variable "clusters" {
  description = "Map of ElastiCache replication groups to create. Key becomes the cluster_key (e.g. \"cache\")."
  type = map(object({
    # ── Engine ────────────────────────────────────────────────────
    engine         = optional(string, "valkey")
    engine_version = optional(string, "8.0")
    node_type      = string

    # Total number of cache clusters (1 = single primary, 2+ = primary + replicas).
    num_cache_clusters = optional(number, 1)

    # Parameter group family (e.g. "valkey8", "redis7"). Derived from engine +
    # major engine_version when null.
    parameter_group_family = optional(string, null)
    # Custom parameter overrides (name => value).
    parameters = optional(map(string), {})

    # ── High availability ──────────────────────────────────────────
    # Both require num_cache_clusters >= 2.
    automatic_failover_enabled = optional(bool, false)
    multi_az_enabled           = optional(bool, false)

    # ── Encryption ────────────────────────────────────────────────
    at_rest_encryption_enabled = optional(bool, true)
    transit_encryption_enabled = optional(bool, true)
    # "preferred" allows both TLS and plain connections; "required" enforces TLS.
    transit_encryption_mode = optional(string, "preferred")
    # Redis AUTH token. Only valid when transit_encryption_enabled = true.
    # Stored in Terraform state — prefer passing via a data.aws_secretsmanager_secret_version.
    auth_token                 = optional(string, null)
    auth_token_update_strategy = optional(string, "ROTATE")

    # ── Maintenance & backups ──────────────────────────────────────
    maintenance_window       = optional(string, "sun:05:00-sun:06:00")
    snapshot_retention_limit = optional(number, 1)
    snapshot_window          = optional(string, "04:00-05:00")

    # ── Observability ─────────────────────────────────────────────
    # When true the module creates a CloudWatch log group and configures
    # ElastiCache slow-log delivery to it.
    slow_log_enabled = optional(bool, false)

    # ── Networking ────────────────────────────────────────────────
    # Additional pre-existing security group IDs to attach (module always
    # creates and attaches one security group per cluster).
    security_group_ids = optional(list(string), [])
    # Ingress rules for the module-managed security group. Map key becomes the
    # Terraform resource key and appears as the AWS rule description.
    security_group_ingress_rules = optional(map(object({
      protocol                     = string
      from_port                    = optional(number, null)
      to_port                      = optional(number, null)
      cidr_ipv4                    = optional(string, null)
      referenced_security_group_id = optional(string, null)
      description                  = optional(string, null)
    })), {})
  }))
  default = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every resource created by this module."
  default     = {}
}
