# AAP RDS Terraform Project Rules

## Context
This project provisions an AWS RDS PostgreSQL instance (db.t3.micro, free tier) to serve
as an external database backend for a containerized Red Hat Ansible Automation Platform
(AAP) 2.7 installation on a single RHEL VM running in VMware Fusion on Apple Silicon.

## Stack
- Terraform (AWS provider) for infrastructure provisioning
- AWS CLI (already authenticated) for verification/debugging
- PostgreSQL 16 on RDS
- Target: AAP 2.7 containerized installer inventory variables (*_pg_host, *_pg_database, etc.)

## File Structure
aap-rds/
├── main.tf          # VPC data sources, security group, subnet group, RDS instance
├── variables.tf     # region, db_password (sensitive), db_username, allowed_cidr
├── outputs.tf       # rds_endpoint, db_username
└── terraform.tfvars # actual values (gitignored)

## Terraform Conventions
- Always use data sources for the default VPC and subnets, never hardcode IDs
- All sensitive variables must have sensitive = true
- Use snake_case for all resource and variable names
- No hardcoded credentials anywhere in .tf files
- terraform.tfvars must be listed in .gitignore
- Run `terraform fmt` before suggesting any .tf file content
- Prefer locals{} over repeated expressions

## Security Rules
- Security group ingress on port 5432 must be scoped to a specific CIDR (allowed_cidr variable), never 0.0.0.0/0
- publicly_accessible = true is acceptable for this PoC only; flag it as a PoC caveat in any suggestions
- skip_final_snapshot = true and backup_retention_period = 0 are acceptable for PoC
- Never suggest multi_az = true for this project (cost/free tier)

## PostgreSQL / AAP Database Conventions
- One RDS instance, multiple databases: aap_gateway, aap_controller, aap_hub
- One dedicated role per database with least-privilege (GRANT on that DB only)
- postgresql_admin_username maps to the RDS master user (aap_admin)
- Always provide psql commands using the RDS endpoint output, not hardcoded hostnames

## AWS CLI Debugging Preferences
- Use --output text for scripting, --output table for human-readable checks
- Always scope aws rds describe-db-instances with --db-instance-identifier aap-postgres
- Use `aws rds wait db-instance-available` before any connection attempt

## Error Handling
- If a Terraform error mentions "unexpected attribute", check variable name alignment between variables.tf and terraform.tfvars first
- If RDS connection is refused, check security group ingress CIDR and that publicly_accessible = true is set
- If psql times out, verify the RHEL VM's outbound IP with `curl -s ifconfig.me` and compare to allowed_cidr

## Output Mapping
After `terraform apply`, map outputs directly to AAP inventory:
- rds_endpoint → gateway_pg_host, controller_pg_host, hub_pg_host
- db_username → postgresql_admin_username

## Out of Scope
- EDA, Metrics, Lightspeed, MCP server components (not deploying)
- Multi-node AAP topology
- NFS/shared storage (single VM, local path for hub_shared_data_path)
- Aurora or any non-RDS postgres option
