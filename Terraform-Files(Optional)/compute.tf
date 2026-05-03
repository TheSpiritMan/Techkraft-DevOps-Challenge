module "compute" {
  source = "./modules/compute"

  depends_on = [module.iam, module.vpc]

  vpc_id = module.vpc.vpc_id

  public_subnets = module.vpc.public_subnet_ids
  private_ec2_subnet_ids = module.vpc.private_ec2_subnet_ids
# private_db_subnet_ids = module.vpc.private_db_subnet_ids
  
  instance_profile = module.iam.instance_profile

  project_name = var.project_name
  environment  = var.environment

  db_secret_arn = module.secrets.db_secret_arn
  db_endpoint   = module.database.db_endpoint
}