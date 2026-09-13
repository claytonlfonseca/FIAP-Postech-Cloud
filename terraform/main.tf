##############################################
# Root module: conecta todos os módulos do
# ToggleMaster (Fase 3 - Parte 1: IaC).
##############################################

module "networking" {
  source   = "./modules/networking"
  name     = var.project_name
  vpc_cidr = var.vpc_cidr
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = "${var.project_name}-eks"
  cluster_version     = var.eks_cluster_version
  vpc_id              = module.networking.vpc_id
  subnet_ids          = module.networking.private_subnet_ids
  node_instance_types = var.eks_node_instance_types
  desired_size        = var.eks_desired_size
  min_size            = var.eks_min_size
  max_size            = var.eks_max_size
}

module "rds" {
  source = "./modules/rds"

  name_prefix                = var.project_name
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  databases                  = var.rds_databases
}

module "elasticache" {
  source = "./modules/elasticache"

  name_prefix                = var.project_name
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
}

module "dynamodb" {
  source     = "./modules/dynamodb"
  table_name = var.dynamodb_table_name
}

module "sqs" {
  source     = "./modules/sqs"
  queue_name = var.sqs_queue_name
}

module "ecr" {
  source           = "./modules/ecr"
  repository_names = var.ecr_repository_names
}
