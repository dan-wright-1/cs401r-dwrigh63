# ── environments/local ───────────────────────────────────────────────────────
# Calls the same modules as environments/dev. The sagemaker module is omitted
# on purpose: SageMaker is not in LocalStack Community.
#
# These calls are live, not commented out, so `make local-validate` works the
# moment your vpc, storage, and iam modules are implemented. Until then,
# terraform validate still passes — an empty module is a valid module.

module "vpc" {
  source      = "../../modules/vpc"
  project     = var.project
  environment = var.environment

  # LocalStack Community does not emulate NAT Gateways.
  enable_nat_gateway = false
}

module "storage" {
  source      = "../../modules/storage"
  project     = var.project
  environment = var.environment

  # Lifecycle rules add nothing to a throwaway emulator.
  enable_lifecycle_rules = false
  force_destroy          = true
}

# Creates all three roles: MLEngineer, DataEngineer, ModelMonitor.
module "iam" {
  source      = "../../modules/iam"
  project     = var.project
  environment = var.environment
}
