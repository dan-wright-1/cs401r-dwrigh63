# ── environments/dev ─────────────────────────────────────────────────────────
# Wire the modules together here. Each module call passes var.project and
# var.environment down; nothing in modules/ hardcodes a name.

module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
  enable_nat_gateway  = true
}

module "storage" {
  source = "../../modules/storage"

  project                = var.project
  environment            = var.environment
  enable_lifecycle_rules = true

  # Synthetic, regenerable lab data: let destroy empty the versioned bucket.
  force_destroy = true
}

module "iam" {
  source = "../../modules/iam"

  project     = var.project
  environment = var.environment
}

module "sagemaker" {
  source = "../../modules/sagemaker"

  project                 = var.project
  environment             = var.environment
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = [module.vpc.private_subnet_id]
  security_group_id       = module.vpc.security_group_id
  execution_role_arn      = module.iam.ml_engineer_role_arn
  sagemaker_instance_type = var.sagemaker_instance_type
}

module "glue" {
  source = "../../modules/glue"

  project                = var.project
  environment            = var.environment
  bucket_name            = module.storage.bucket_name
  data_engineer_role_arn = module.iam.data_engineer_role_arn
  subnet_id              = module.vpc.private_subnet_id
  availability_zone      = module.vpc.private_subnet_availability_zone
  security_group_id      = module.vpc.security_group_id
  scripts_dir            = "${path.root}/../../../glue-scripts"
}
