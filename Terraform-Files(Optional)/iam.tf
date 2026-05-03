module "iam" {
  source = "./modules/iam"

  project_name  = var.project_name
  environment   = var.environment
  db_secret_arn = module.secrets.db_secret_arn
}