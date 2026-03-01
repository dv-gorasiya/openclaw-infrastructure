locals {
  common_tags = merge(
    {
      Project     = "OpenClaw"
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

module "networking" {
  source = "./modules/networking"

  environment       = var.environment
  vpc_cidr          = var.vpc_cidr
  subnet_cidr       = var.subnet_cidr
  availability_zone = var.availability_zone
  openclaw_ports    = var.openclaw_ports
  tags              = local.common_tags
}

module "security" {
  source = "./modules/security"

  environment       = var.environment
  enable_cloudtrail = var.enable_cloudtrail
  tags              = local.common_tags
}

module "storage" {
  source = "./modules/storage"

  environment            = var.environment
  availability_zone      = var.availability_zone
  ebs_volume_size        = var.ebs_volume_size
  backup_retention_days  = var.backup_retention_days
  backup_retention_weeks = var.backup_retention_weeks
  tags                   = local.common_tags
}

module "compute" {
  source = "./modules/compute"

  environment          = var.environment
  availability_zone    = var.availability_zone
  instance_type        = var.instance_type
  vpc_id               = module.networking.vpc_id
  subnet_id            = module.networking.subnet_id
  instance_sg_id       = module.networking.instance_sg_id
  iam_instance_profile = module.security.instance_profile_name
  ebs_volume_id        = module.storage.ebs_volume_id
  secrets_manager_arn  = module.security.secrets_manager_arn
  secrets_manager_name = module.security.secrets_manager_name
  openclaw_ports       = var.openclaw_ports
  tags                 = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  environment        = var.environment
  alert_email        = var.alert_email
  instance_id        = module.compute.instance_id
  asg_name           = module.compute.asg_name
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}
