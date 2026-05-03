module "database" {
  source = "./modules/database"

  depends_on = [module.secrets]

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_db_subnet_ids = module.vpc.private_db_subnet_ids
  app_sg_id             = module.compute.app_sg_id
  db_secret_arn         = module.secrets.db_secret_arn
}