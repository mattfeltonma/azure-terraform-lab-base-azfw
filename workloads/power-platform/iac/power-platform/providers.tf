# Setup providers
provider "azapi" {
}

provider "azapi" {
  alias           = "subscription_billing"
  subscription_id = var.subscription_id_billing
}

provider "powerplatform" {
}

provider "time" {
}

provider "null" {
}