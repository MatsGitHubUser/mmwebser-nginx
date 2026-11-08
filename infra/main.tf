terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Settings are passed with -backend-config by the workflow.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}

  # The CI identity only has access to one resource group, so it cannot
  # register providers. scripts/bootstrap-azure.sh registers them instead.
  resource_provider_registrations = "none"
}

# Created by scripts/bootstrap-azure.sh, which also scopes CI access to it.
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Kept while stopped: it is free and holds the app's stable domain.
resource "azurerm_container_app_environment" "main" {
  name                = "cae-${var.name}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_container_app" "web" {
  count = var.running ? 1 : 0

  name                         = "ca-${var.name}"
  resource_group_name          = data.azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"

  ingress {
    external_enabled = true
    target_port      = 8080

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = 1

    container {
      name   = "web"
      image  = var.image
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  lifecycle {
    precondition {
      condition     = var.image != ""
      error_message = "image must be set when running = true."
    }
  }
}
