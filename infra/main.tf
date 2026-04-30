 # ===========================================================================
# main.tf — Cloud News Aggregator (Consolidated)
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. External Data Sources
# ---------------------------------------------------------------------------

data "aws_route53_zone" "main" {
  name = var.domain_name # Replace with your actual domain
}

# ---------------------------------------------------------------------------
# 2. Core Infrastructure & Storage
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "cna" {
  name     = "rg-${var.project}-${var.environment}"
  location = var.azure_location
  tags     = var.tags
}

resource "azurerm_storage_account" "feeds" {
  name                     = "st${var.project}${var.environment}"
  resource_group_name      = azurerm_resource_group.cna.name
  location                 = azurerm_resource_group.cna.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  tags                     = var.tags
}

# Auto-delete old digests based on your retention variable
resource "azurerm_storage_management_policy" "retention" {
  storage_account_id = azurerm_storage_account.feeds.id
  rule {
    name    = "expire-digests"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = var.blob_retention_days
      }
    }
  }
}

# ---------------------------------------------------------------------------
# 3. Email Infrastructure (ACS)
# ---------------------------------------------------------------------------

resource "azurerm_communication_service" "main" {
  name                = "acs-${var.project}-${var.environment}"
  resource_group_name = azurerm_resource_group.cna.name
  data_location       = "United States"
}

resource "azurerm_email_communication_service" "email" {
  name                = "email-${var.project}-${var.environment}"
  resource_group_name = azurerm_resource_group.cna.name
  data_location       = "United States"
}

resource "azurerm_email_communication_service_domain" "custom" {
  name              = "mail.${var.domain_name}"
  email_service_id  = azurerm_email_communication_service.email.id
  domain_management = "CustomerManaged"
}

# ---------------------------------------------------------------------------
# 4. Route 53 Records
# ---------------------------------------------------------------------------

resource "aws_route53_record" "verify" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = azurerm_email_communication_service_domain.custom.verification_records[0].domain[0].name
  type    = "TXT"
  ttl     = 3600
  records = [azurerm_email_communication_service_domain.custom.verification_records[0].domain[0].value]
}

resource "aws_route53_record" "spf" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = azurerm_email_communication_service_domain.custom.verification_records[0].spf[0].name
  type    = "TXT"
  ttl     = 3600
  records = [azurerm_email_communication_service_domain.custom.verification_records[0].spf[0].value]
}

resource "aws_route53_record" "dkim1" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = azurerm_email_communication_service_domain.custom.verification_records[0].dkim[0].name
  type    = "CNAME"
  ttl     = 3600
  records = [azurerm_email_communication_service_domain.custom.verification_records[0].dkim[0].value]
}

resource "aws_route53_record" "dkim2" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = azurerm_email_communication_service_domain.custom.verification_records[0].dkim2[0].name
  type    = "CNAME"
  ttl     = 3600
  records = [azurerm_email_communication_service_domain.custom.verification_records[0].dkim2[0].value]
}

# Recommended DMARC record to protect domain reputation
resource "aws_route53_record" "dmarc" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "_dmarc.mail.yourdomain.com"
  type    = "TXT"
  ttl     = 3600
  records = ["v=DMARC1; p=quarantine;"]
}

# ---------------------------------------------------------------------------
# 5. Automating the "Final Click" (Verification Actions)
# ---------------------------------------------------------------------------

resource "azapi_resource_action" "initiate_verification" {
  for_each    = toset(["Domain", "SPF", "DKIM", "DKIM2"])
  type        = "Microsoft.Communication/emailServices/domains@2023-03-31"
  resource_id = azurerm_email_communication_service_domain.custom.id
  action      = "initiateVerification"
  body        = jsonencode({ verificationType = each.key })

  # Ensure DNS records exist before triggering verification
  depends_on = [
    aws_route53_record.verify,
    aws_route53_record.spf,
    aws_route53_record.dkim1,
    aws_route53_record.dkim2
  ]
}

# ---------------------------------------------------------------------------
# 6. Linking & Sender Setup
# ---------------------------------------------------------------------------

# Link verified domain to ACS
resource "azurerm_communication_service_email_domain_association" "link" {
  communication_service_id = azurerm_communication_service.main.id
  email_service_domain_id  = azurerm_email_communication_service_domain.custom.id
}

# Create the specific "From" username (e.g., digest@mail.yourdomain.com)
resource "azurerm_email_communication_service_domain_sender_username" "digest" {
  name                   = split("@", var.email_sender_address)[0]
  email_service_domain_id = azurerm_email_communication_service_domain.custom.id
  display_name           = "News Aggregator Digest"
}

# ---------------------------------------------------------------------------
# 7. Serverless Logic (Function App)
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "plan" {
  name                = "asp-${var.project}-${var.environment}"
  resource_group_name = azurerm_resource_group.cna.name
  location            = azurerm_resource_group.cna.location
  os_type             = "Linux"
  sku_name            = var.function_app_sku
}

resource "azurerm_linux_function_app" "aggregator" {
  name                = "func-${var.project}-${var.environment}"
  resource_group_name = azurerm_resource_group.cna.name
  location            = azurerm_resource_group.cna.location

  storage_account_name       = azurerm_storage_account.feeds.name
  storage_account_access_key = azurerm_storage_account.feeds.primary_access_key
  service_plan_id            = azurerm_service_plan.plan.id

  site_config {
    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = {
    "CLAUDE_MODEL"              = var.claude_model
    "AI_MAX_TOKENS"             = var.ai_max_tokens
    "SENDER_EMAIL"              = var.email_sender_address
    "RECIPIENT_EMAIL"           = var.email_recipient_address
    "STORAGE_CONNECTION_STRING" = azurerm_storage_account.feeds.primary_connection_string
    "ACS_CONNECTION_STRING"     = azurerm_communication_service.main.primary_connection_string
  }
}
