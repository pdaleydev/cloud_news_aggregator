terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state in Azure Blob Storage.
  # The storage account and container must be created manually (or via a
  # bootstrap script) before running `terraform init` for the first time,
  # because Terraform cannot manage the very bucket that holds its own state.
  #
  # Values are intentionally left blank here and supplied via:
  #   - CI/CD: environment variables (ARM_ACCESS_KEY or managed identity)
  #   - Local dev: `terraform init -backend-config=backend.hcl` (git-ignored)
  backend "azurerm" {
    resource_group_name  = "rg-cloud-news-aggregator-tfstate"
    storage_account_name = "stcloudnewsaggrtfstate"  # must be globally unique
    container_name       = "tfstate"
    key                  = "cloud-news-aggregator.terraform.tfstate"
  }
}

# ---------------------------------------------------------------------------
# AzureRM — the primary provider for all Azure resources.
#
# Authentication order (azurerm tries these in sequence):
#   1. Environment variables (ARM_CLIENT_ID / ARM_CLIENT_SECRET / ARM_TENANT_ID)
#   2. Managed Identity (used automatically inside GitHub Actions with OIDC,
#      and on any Azure-hosted runner)
#   3. Azure CLI (`az login`) — convenient for local development
#
# No credentials are hard-coded here. The subscription_id is the only
# non-secret value pinned, which makes plan output readable and avoids
# accidentally targeting the wrong subscription.
# ---------------------------------------------------------------------------
provider "azurerm" {
  features {
    # Purge Key Vault on destroy so the soft-deleted vault doesn't block
    # re-creates during iterative development. Set to false in production
    # if you want the 90-day recovery window.
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    # Prevent accidental deletion of the resource group if it still contains
    # resources Terraform doesn't know about (e.g. manually created items).
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  subscription_id = var.azure_subscription_id
}

# AWS for Route 53 Records to be able to send emails from my domain.
provider "aws" {
  region                   = var.aws_region
  shared_credentials_files = [var.aws_credential_path]
  profile                  = var.aws_user
}

# ---------------------------------------------------------------------------
# AzureAD — needed to look up the current principal's object ID so we can
# grant it Key Vault access policies during development without hard-coding
# any UUIDs. In CI the principal is the GitHub Actions service principal.
# ---------------------------------------------------------------------------
provider "azuread" {}

# ---------------------------------------------------------------------------
# Random — used to append a short suffix to globally-unique resource names
# (storage accounts, Key Vault) so multiple environments (dev/staging/prod)
# can coexist without naming collisions.
# ---------------------------------------------------------------------------
provider "random" {}
