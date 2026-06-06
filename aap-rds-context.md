# AAP RDS Project — Warp AI Context File

## Project Goal
Provision an external AWS RDS PostgreSQL 16 instance (db.t3.micro, free tier) to serve
as the database backend for a containerized Red Hat Ansible Automation Platform (AAP) 2.7
PoC deployment. PostgreSQL is offloaded to RDS to relieve resource pressure on the RHEL VM.

## Host Environment
- **Mac** (Apple Silicon, ~14 GB RAM free) running VMware Fusion
- **RHEL VM**: 4 vCPUs, 4 GB RAM, 60 GB storage — tight for a full AAP stack
- **AWS CLI**: authenticated and working
- **Terraform**: installed, used for all infrastructure provisioning
- **AWS Region**: us-west-1

## AAP Deployment Scope (PoC — minimal)
Only these components are deployed on the RHEL VM:
- `[automationgateway]`
- `[automationcontroller]`
- `[automationhub]`
- `[redis]` (local to VM)

Skipped (comment out in inventory):
- `[automationeda]` — too RAM-heavy
- `[automationmetrics]` — not needed for PoC
- `[ansiblelightspeed]` / `[ansiblemcp]` — out of scope

## Terraform Project Structure
```
~/dev/IaC/aap-rds/
├── main.tf          # Provider, VPC data sources, security group, subnet group, RDS instance
├── variables.tf     # region, db_password (sensitive), db_username, allowed_cidr
├── outputs.tf       # rds_endpoint, db_username
├── terraform.tfvars # Non-secret vars only (region, db_username placeholder)
└── secrets.tfvars   # Gitignored — db_password and allowed_cidr
```

**Run with:**
```bash
terraform apply -var-file="terraform.tfvars" -var-file="secrets.tfvars"
```

**Or use env vars instead of secrets.tfvars (preferred):**
```bash
export TF_VAR_db_password="..."
export TF_VAR_allowed_cidr="$(curl -s ifconfig.me)/32"
terraform apply -var-file="terraform.tfvars"
```

## main.tf (current)
```hcl
provider "aws" {
  region = var.region
}

data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

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

resource "aws_db_subnet_group" "aap" {
  name       = "aap-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "aap_postgres" {
  identifier        = "aap-postgres"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "aap_gateway"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.aap.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = true

  skip_final_snapshot      = true
  delete_automated_backups = true
  multi_az                 = false
  backup_retention_period  = 0
}
```

## variables.tf (current)
```hcl
variable "region"       { default = "us-west-1" }
variable "db_password"  { sensitive = true }
variable "db_username"  { default = "aap_admin" }
variable "allowed_cidr" { description = "RHEL VM public IP in CIDR, e.g. 1.2.3.4/32" }
```

## outputs.tf (current)
```hcl
output "rds_endpoint" {
  value = aws_db_instance.aap_postgres.endpoint
}
output "db_username" {
  value = var.db_username
}
```

## terraform.tfvars (non-secret placeholder values shown)
```hcl
# No secrets here — use TF_VAR_* env vars or secrets.tfvars (gitignored)
# db_password  → TF_VAR_db_password
# allowed_cidr → TF_VAR_allowed_cidr or secrets.tfvars
```

## AAP Inventory Variable Mapping
After `terraform apply`, map the RDS endpoint to these AAP inventory variables:
```ini
[all:vars]
# DB host — use the full .rds.amazonaws.com hostname from terraform output rds_endpoint
gateway_pg_host=<rds_endpoint>
gateway_pg_database=aap_gateway
gateway_pg_username=aap_gateway
gateway_pg_password=<role_password>

controller_pg_host=<rds_endpoint>
controller_pg_database=aap_controller
controller_pg_username=aap_controller
controller_pg_password=<role_password>

hub_pg_host=<rds_endpoint>
hub_pg_database=aap_hub
hub_pg_username=aap_hub
hub_pg_password=<role_password>

postgresql_admin_username=aap_admin
postgresql_admin_password=<master_password>
```

One RDS instance hosts all three databases. Each database has a dedicated least-privilege role.

## Post-Apply: Create Databases and Roles
```bash
ENDPOINT=$(terraform output -raw rds_endpoint | cut -d: -f1)

psql -h $ENDPOINT -U aap_admin -d aap_gateway <<'EOF'
CREATE DATABASE aap_controller;
CREATE ROLE aap_controller WITH LOGIN PASSWORD 'pick_a_password';
GRANT ALL PRIVILEGES ON DATABASE aap_controller TO aap_controller;

CREATE DATABASE aap_hub;
CREATE ROLE aap_hub WITH LOGIN PASSWORD 'pick_a_password';
GRANT ALL PRIVILEGES ON DATABASE aap_hub TO aap_hub;

CREATE ROLE aap_gateway WITH LOGIN PASSWORD 'pick_a_password';
GRANT ALL PRIVILEGES ON DATABASE aap_gateway TO aap_gateway;
EOF
```

## Terraform Conventions
- Use data sources for default VPC/subnets — never hardcode IDs
- All sensitive variables must have `sensitive = true`
- snake_case for all resource and variable names
- No hardcoded credentials in .tf files
- `terraform.tfvars` and `secrets.tfvars` are gitignored
- Run `terraform fmt` before committing

## Security Notes (PoC caveats)
- `publicly_accessible = true` — acceptable for PoC only; lock down in production
- Security group ingress scoped to `allowed_cidr` — never 0.0.0.0/0
- `skip_final_snapshot = true` and `backup_retention_period = 0` — PoC only
- `multi_az = false` — PoC only, no HA needed

## Common Errors & Fixes
| Error | Likely cause | Fix |
|---|---|---|
| "Reference to undeclared resource" in outputs.tf | outputs.tf content was embedded as a comment inside main.tf | Split into separate files: main.tf, outputs.tf, variables.tf |
| "Unexpected attribute" in tfvars | Variable name mismatch between variables.tf and tfvars file | Run `grep variable variables.tf` and verify names match exactly |
| psql connection refused | Security group CIDR doesn't match outbound IP | `curl -s ifconfig.me` on RHEL VM; update `allowed_cidr` |
| psql connection timeout | `publicly_accessible` not set or wrong subnet | Verify `publicly_accessible = true` and subnet group uses default VPC subnets |

## AWS CLI Verification Commands
```bash
# Check instance status
aws rds describe-db-instances \
  --db-instance-identifier aap-postgres \
  --query "DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}" \
  --output table

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids <SG_ID> \
  --query "SecurityGroups[0].IpPermissions" \
  --output table

# Wait for available state
aws rds wait db-instance-available --db-instance-identifier aap-postgres
```

## Out of Scope
- EDA, Metrics, Lightspeed, MCP server (not deploying)
- Multi-node AAP topology
- NFS/shared storage
- Aurora or non-RDS postgres
- Multi-AZ or production hardening
