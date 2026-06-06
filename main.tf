provider "aws" {
  region = var.region
}

# Reuse your default VPC and subnets — no new VPC needed for a PoC
data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group: allow port 5432 only from your RHEL VM
resource "aws_security_group" "rds_sg" {
  name   = "aap-rds-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Subnet group required by RDS
resource "aws_db_subnet_group" "aap" {
  name       = "aap-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

# RDS instance — free tier eligible
resource "aws_db_instance" "aap_postgres" {
  identifier        = "aap-postgres"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "aap_gateway" # create one DB now; add others via psql after
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.aap.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = true

  skip_final_snapshot      = true
  delete_automated_backups = true
  multi_az                 = false
  backup_retention_period  = 0 # disable backups for PoC
}
