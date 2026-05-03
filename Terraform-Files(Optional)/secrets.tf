module "secrets" {
  source = "./modules/secrets"

  project_name = var.project_name
  environment  = var.environment
}