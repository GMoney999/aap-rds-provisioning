# AGENTS.md

## Purpose
This repository provisions a PoC AWS RDS PostgreSQL instance for Red Hat Ansible Automation Platform (AAP) 2.7.

Primary goals:
- Create a single RDS PostgreSQL instance (`aap-postgres`)
- Expose outputs needed by AAP inventory (`rds_endpoint`, `db_username`)
- Keep security and cost posture aligned with PoC constraints

## Repository Layout
- `main.tf`: AWS provider, default VPC/subnet data sources, security group, DB subnet group, RDS instance
- `variables.tf`: input variables (`region`, `db_username`, `db_password`, `allowed_cidr`)
- `outputs.tf`: exported values for downstream use
- `terraform.tfvars`: non-secret or placeholder values
- `secrets.tfvars`: sensitive local values (must remain uncommitted)
- `inventory`: AAP installer inventory template and variable mapping target
- `TEARDOWN.md`: supplemental cleanup runbook to avoid lingering AWS costs
- `RULES.md`: project conventions and guardrails
- `aap-rds-context.md`: deeper project background and operational notes

## Current Known Blocker
Running `terraform plan` currently fails with:
- `Error: no matching EC2 VPC found`
- Source: `data "aws_vpc" "default" { default = true }` in `main.tf`

Interpretation:
- The target AWS account/region does not have a default VPC, so data lookups for `aws_vpc.default` and `aws_subnets.default` fail.

When fixing this, prefer one of:
1. Parameterize VPC/subnet IDs via variables and use those instead of default-VPC data lookups.
2. Keep current approach only if a default VPC is confirmed to exist in the target account/region.

## Agent Workflow
1. Read `RULES.md` and `aap-rds-context.md` first.
2. Run formatting and validation before proposing infra changes:
   - `terraform fmt`
   - `terraform validate`
3. Use plan/apply with explicit var files or `TF_VAR_*` env vars:
   - `terraform plan -var-file="terraform.tfvars" -var-file="secrets.tfvars"`
   - `terraform apply -var-file="terraform.tfvars" -var-file="secrets.tfvars"`
4. After successful apply, use outputs to update `inventory` DB host variables.

## Security and Safety Rules
- Never commit secrets or plaintext passwords.
- Never broaden Postgres ingress to world-open CIDRs.
- `publicly_accessible = true` is PoC-only and should be called out in recommendations.
- Keep `multi_az = false` for this PoC unless requirements explicitly change.

## Terraform Change Guidelines
- Avoid hardcoding resource IDs unless explicitly required.
- Keep variable names aligned across `variables.tf` and tfvars files.
- Preserve output names consumed by AAP mapping unless a migration plan is provided.
- Prefer minimal, focused changes; avoid refactoring unrelated resources.

## Validation Checklist for Changes
Before finalizing Terraform edits:
- `terraform fmt` passes
- `terraform validate` passes
- `terraform plan` runs and explains intended resource deltas
- Any change to networking is explicitly reviewed for CIDR correctness

## Out of Scope (for this repo)
- Multi-node AAP topology design
- Non-RDS database options (Aurora, self-managed alternatives)
- Production HA/hardening baseline beyond current PoC constraints

## Cost Control
- Always consult `TEARDOWN.md` before pausing or ending PoC work so chargeable RDS resources are removed.
