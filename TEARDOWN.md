# TEARDOWN.md

## Goal
Remove all AWS resources created for this PoC so no ongoing RDS-related costs remain.

Most likely chargeable items:
- RDS instance (`aap-postgres`)
- Manual DB snapshots (if any were created)
- Retained automated backups (if any exist)

## Quick Start (Recommended)
Use the helper script first:

```bash
./teardown.sh --dry-run
./teardown.sh
```

Useful options:

```bash
./teardown.sh --yes
./teardown.sh --no-fallback
```

## Pre-Teardown Checks
Run these first to confirm you are operating in the intended account and region:

```bash
aws sts get-caller-identity --output table
aws configure get region
```

Optional quick presence check:

```bash
aws rds describe-db-instances \
  --db-instance-identifier aap-postgres \
  --query "DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}" \
  --output table
```

## Preferred Path: Terraform Destroy
Use Terraform first when state is intact.

```bash
terraform init
terraform plan -destroy -var-file="terraform.tfvars" -var-file="secrets.tfvars"
terraform destroy -var-file="terraform.tfvars" -var-file="secrets.tfvars"
```

If you are using environment variables instead of `secrets.tfvars`:

```bash
export TF_VAR_db_password="{{db_password}}"
export TF_VAR_allowed_cidr="$(curl -s ifconfig.me)/32"
terraform plan -destroy -var-file="terraform.tfvars"
terraform destroy -var-file="terraform.tfvars"
```

## Post-Destroy Verification (Cost Safety)
Confirm there is no chargeable RDS footprint left.

1) Confirm instance is gone:

```bash
aws rds describe-db-instances \
  --db-instance-identifier aap-postgres \
  --query "DBInstances[0].DBInstanceIdentifier" \
  --output text
```

Expected: not found error.

2) Confirm no manual snapshots remain:

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier aap-postgres \
  --snapshot-type manual \
  --query "DBSnapshots[].DBSnapshotIdentifier" \
  --output text
```

Expected: empty output.

3) Confirm no automated backup artifacts remain:

```bash
aws rds describe-db-instance-automated-backups \
  --db-instance-identifier aap-postgres \
  --query "DBInstanceAutomatedBackups[].DBInstanceIdentifier" \
  --output text
```

Expected: empty output.

## Fallback Path: Manual Cleanup
Use this when `terraform destroy` cannot proceed (for example, state/config drift or provider data-source failures).

1) Delete the DB instance without final snapshot:

```bash
aws rds delete-db-instance \
  --db-instance-identifier aap-postgres \
  --skip-final-snapshot \
  --delete-automated-backups
```

2) Wait for deletion to complete:

```bash
aws rds wait db-instance-deleted --db-instance-identifier aap-postgres
```

3) Delete any manual snapshots left behind:

```bash
SNAPSHOTS=$(aws rds describe-db-snapshots \
  --db-instance-identifier aap-postgres \
  --snapshot-type manual \
  --query "DBSnapshots[].DBSnapshotIdentifier" \
  --output text)

for SNAPSHOT in $SNAPSHOTS; do
  aws rds delete-db-snapshot --db-snapshot-identifier "$SNAPSHOT"
done
```

4) Delete the DB subnet group:

```bash
aws rds delete-db-subnet-group --db-subnet-group-name aap-subnet-group
```

5) Delete the security group (if it still exists):

```bash
SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=aap-rds-sg \
  --query "SecurityGroups[0].GroupId" \
  --output text)

if [ "$SG_ID" != "None" ]; then
  aws ec2 delete-security-group --group-id "$SG_ID"
fi
```

6) Re-run the verification commands from the previous section.

## Notes
- For strict cost control, avoid creating manual snapshots before teardown.
- `skip_final_snapshot = true` and `delete_automated_backups = true` are aligned with this PoC’s cost-minimization goal.
- If you intentionally keep snapshots for recovery, expect snapshot storage charges until they are deleted.
