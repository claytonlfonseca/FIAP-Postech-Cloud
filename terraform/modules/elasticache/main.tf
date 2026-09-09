##############################################
# ElastiCache (Redis) — 1 cluster de replicação.
# Auth token gerado localmente e exposto apenas
# via output sensível (recomenda-se migrar para
# Secrets Manager em uma fase futura).
##############################################

resource "random_password" "auth_token" {
  length  = 32
  special = false
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-redis-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.name_prefix}-redis-sg-"
  description = "Permite acesso Redis somente a partir do EKS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis vindo do EKS"
    from_port       = 6379
    to_port         = 6379
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
    Name = "${var.name_prefix}-redis-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis cluster para ToggleMaster"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type

  num_cache_clusters = var.num_cache_clusters
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.auth_token.result

  tags = {
    Name = "${var.name_prefix}-redis"
  }
}
