# ===========================================================================
# variables.tf — Cloud News Aggregator
#
# All inputs to the Terraform configuration are declared here.
# Values are supplied via:
#   - terraform.tfvars        (local dev, git-ignored)
#   - TF_VAR_* env variables  (CI/CD pipeline)
#
# Secrets (API keys, SMTP credentials) are NOT inputs here — they are
# written directly into Key Vault by a separate secrets-bootstrap step
# and referenced by the Function App via Key Vault references.
# ===========================================================================


# ---------------------------------------------------------------------------
# Core / global
# ---------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription ID to deploy all resources into."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid lowercase UUID."
  }
}

variable "location" {
  description = "Azure region for all resources (e.g. 'eastus', 'westeurope')."
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Development environment. Controls naming suffixes and certain behaviour (e.g. Key Vault purge policy)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "project" {
  description = "Short project token used in resource names. Lowercase letters and hyphens only."
  type        = string
  default     = "cna" # cloud-news-aggregator
}

variable "tags" {
  description = "Additional tags merged onto every resource. The module already applies project, environment, and managed-by tags automatically."
  type        = map(string)
  default     = {}
}


# ---------------------------------------------------------------------------
# Networking / access
# ---------------------------------------------------------------------------

variable "allowed_ip_ranges" {
  description = <<-EOT
    List of your own public IP CIDR ranges allowed to reach the storage
    account and Key Vault management plane directly (e.g. for local
    terraform apply or manual inspection). Leave empty to restrict to
    Azure services only.
    Example: ["203.0.113.42/32"]
  EOT
  type        = list(string)
  default     = []
}


# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

variable "storage_replication_type" {
  description = "Replication strategy for the main storage account. LRS is fine for dev; ZRS or GRS for production."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Must be a valid Azure storage replication type."
  }
}

variable "blob_retention_days" {
  description = "Number of days to retain daily JSON blobs before automatic deletion. 30 days covers ~4 weekly wrap-ups."
  type        = number
  default     = 30

  validation {
    condition     = var.blob_retention_days >= 7 && var.blob_retention_days <= 365
    error_message = "blob_retention_days must be between 7 and 365."
  }
}


# ---------------------------------------------------------------------------
# Function App
# ---------------------------------------------------------------------------

variable "function_app_sku" {
  description = "App Service Plan SKU for the Function App. Y1 = Consumption (serverless, pay-per-use). EP1 = Elastic Premium if you need VNet integration or longer timeouts."
  type        = string
  default     = "Y1"

  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_sku)
    error_message = "function_app_sku must be Y1 (Consumption) or EPx (Elastic Premium)."
  }
}

variable "python_version" {
  description = "Python runtime version for the Function App."
  type        = string
  default     = "3.11"

  validation {
    condition     = contains(["3.10", "3.11", "3.12"], var.python_version)
    error_message = "python_version must be 3.10, 3.11, or 3.12."
  }
}

variable "daily_trigger_cron" {
  description = <<-EOT
    NCRONTAB expression for the daily RSS fetch function.
    Azure Functions uses 6-field NCRONTAB: {second} {minute} {hour} {day} {month} {day-of-week}
    Default: 06:00 UTC every day.
  EOT
  type        = string
  default     = "0 0 6 * * *"
}

variable "weekly_trigger_cron" {
  description = <<-EOT
    NCRONTAB expression for the weekly wrap-up function.
    Default: 07:00 UTC every Sunday (giving the daily run an hour to complete first).
  EOT
  type        = string
  default     = "0 0 7 * * 0"
}


# ---------------------------------------------------------------------------
# AI
# ---------------------------------------------------------------------------

variable "claude_model" {
  description = "Anthropic model ID to use for analysis and wrap-up. Stored as a Function App env var so it can be changed without redeployment."
  type        = string
  default     = "claude-sonnet-4-20250514"
}

variable "ai_max_tokens" {
  description = "Maximum tokens per Claude API response. 1024 is plenty for a daily digest; the weekly wrap-up may need more."
  type        = number
  default     = 1024

  validation {
    condition     = var.ai_max_tokens >= 256 && var.ai_max_tokens <= 8192
    error_message = "ai_max_tokens must be between 256 and 8192."
  }
}


# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

variable "email_sender_address" {
  description = "The 'From' address used by Azure Communication Services. Must be a verified domain address in your ACS resource."
  type        = string
  # default     = "digest@cloudnewsaggregator.com"
}

variable "email_recipient_address" {
  description = "Address(es) the daily digest and weekly wrap-up are sent to. Comma-separated for multiple recipients."
  type        = string
  # No default — this must always be set explicitly.
}


# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

variable "alert_email" {
  description = "Email address for Azure Monitor operational alerts (failed runs, cost thresholds). Can be the same as email_recipient_address."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Azure cost budget in USD. An alert fires at 80% and 100% of this value."
  type        = number
  default     = 20

  validation {
    condition     = var.monthly_budget_usd >= 5
    error_message = "monthly_budget_usd must be at least $5."
  }
}
