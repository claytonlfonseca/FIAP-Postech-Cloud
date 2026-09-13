##############################################
# RDS PostgreSQL — 1 instância por serviço.
# As credenciais são geradas e geridas pela AWS
# (manage_master_user_password), evitando senhas
# em texto plano em arquivos/tfvars.
##############################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.name_prefix}-rds-sg-"
  description = "Permite acesso PostgreSQL somente a partir do EKS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL vindo do EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  for_each = var.databases

  identifier     = "${var.name_prefix}-${each.key}"
  db_name        = each.value.db_name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  username                    = var.master_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                = false
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 1

  tags = {
    Name    = "${var.name_prefix}-${each.key}"
    Service = each.key
  }
}
