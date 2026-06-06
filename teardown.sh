#!/usr/bin/env bash
set -euo pipefail

DB_INSTANCE_ID="${DB_INSTANCE_ID:-aap-postgres}"
DB_SUBNET_GROUP_NAME="${DB_SUBNET_GROUP_NAME:-aap-subnet-group}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-aap-rds-sg}"

AUTO_APPROVE=0
DRY_RUN=0
ENABLE_MANUAL_FALLBACK=1

usage() {
  cat <<'EOF'
Usage: ./teardown.sh [options]

Safely tears down PoC AWS resources with explicit confirmations.

Options:
  -y, --yes          Auto-approve confirmation prompts
      --dry-run      Print commands instead of executing them
      --no-fallback  Disable manual AWS CLI fallback if Terraform destroy fails
  -h, --help         Show this help

Optional environment overrides:
  DB_INSTANCE_ID         (default: aap-postgres)
  DB_SUBNET_GROUP_NAME   (default: aap-subnet-group)
  SECURITY_GROUP_NAME    (default: aap-rds-sg)
EOF
}

log() {
  printf '[teardown] %s\n' "$*"
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY RUN:'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  else
    "$@"
  fi
}

confirm() {
  local prompt="$1"
  if [[ "$AUTO_APPROVE" -eq 1 ]]; then
    log "Auto-approved: $prompt"
    return 0
  fi

  local answer
  read -r -p "$prompt [y/N] " answer
  case "${answer:-}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)
        AUTO_APPROVE=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --no-fallback)
        ENABLE_MANUAL_FALLBACK=0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

build_tf_var_args() {
  TF_VAR_ARGS=()
  if [[ -f terraform.tfvars ]]; then
    TF_VAR_ARGS+=("-var-file=terraform.tfvars")
  fi
  if [[ -f secrets.tfvars ]]; then
    TF_VAR_ARGS+=("-var-file=secrets.tfvars")
  fi
}

pre_teardown_checks() {
  log "Running pre-teardown identity checks"
  run_cmd aws sts get-caller-identity --output table
  run_cmd aws configure get region
}

terraform_destroy_path() {
  log "Using Terraform destroy path"
  run_cmd terraform init
  run_cmd terraform plan -destroy "${TF_VAR_ARGS[@]}"

  if ! confirm "Proceed with terraform destroy for ${DB_INSTANCE_ID}?"; then
    log "Cancelled before terraform destroy"
    return 1
  fi

  run_cmd terraform destroy -auto-approve "${TF_VAR_ARGS[@]}"
}

manual_cleanup_path() {
  log "Running manual AWS CLI cleanup fallback"
  run_cmd aws rds delete-db-instance \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --skip-final-snapshot \
    --delete-automated-backups

  run_cmd aws rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_ID"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd aws rds describe-db-snapshots \
      --db-instance-identifier "$DB_INSTANCE_ID" \
      --snapshot-type manual \
      --query "DBSnapshots[].DBSnapshotIdentifier" \
      --output text
    log "DRY RUN: delete each returned manual snapshot via aws rds delete-db-snapshot"
  else
    local snapshots
    snapshots="$(aws rds describe-db-snapshots \
      --db-instance-identifier "$DB_INSTANCE_ID" \
      --snapshot-type manual \
      --query "DBSnapshots[].DBSnapshotIdentifier" \
      --output text || true)"

    for snapshot in $snapshots; do
      if [[ "$snapshot" != "None" ]]; then
        run_cmd aws rds delete-db-snapshot --db-snapshot-identifier "$snapshot"
      fi
    done
  fi

  run_cmd aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP_NAME"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd aws ec2 describe-security-groups \
      --filters "Name=group-name,Values=${SECURITY_GROUP_NAME}" \
      --query "SecurityGroups[0].GroupId" \
      --output text
    log "DRY RUN: delete security group if GroupId is present"
  else
    local sg_id
    sg_id="$(aws ec2 describe-security-groups \
      --filters "Name=group-name,Values=${SECURITY_GROUP_NAME}" \
      --query "SecurityGroups[0].GroupId" \
      --output text || true)"

    if [[ -n "${sg_id:-}" && "$sg_id" != "None" ]]; then
      run_cmd aws ec2 delete-security-group --group-id "$sg_id"
    fi
  fi
}

post_teardown_verification() {
  log "Running post-teardown verification"
  run_cmd aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query "DBInstances[0].DBInstanceIdentifier" \
    --output text
  run_cmd aws rds describe-db-snapshots \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --snapshot-type manual \
    --query "DBSnapshots[].DBSnapshotIdentifier" \
    --output text
  run_cmd aws rds describe-db-instance-automated-backups \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query "DBInstanceAutomatedBackups[].DBInstanceIdentifier" \
    --output text
}

main() {
  parse_args "$@"

  pre_teardown_checks

  if ! confirm "Continue teardown sequence for ${DB_INSTANCE_ID}?"; then
    log "Cancelled by user"
    exit 1
  fi

  build_tf_var_args

  local terraform_ok=0
  if command -v terraform >/dev/null 2>&1; then
    if terraform_destroy_path; then
      terraform_ok=1
    else
      log "Terraform destroy path failed or was cancelled"
    fi
  else
    log "Terraform not found; skipping Terraform path"
  fi

  if [[ "$terraform_ok" -ne 1 ]]; then
    if [[ "$ENABLE_MANUAL_FALLBACK" -ne 1 ]]; then
      log "Manual fallback disabled; exiting without cleanup"
      exit 1
    fi

    if ! confirm "Terraform path did not complete. Run manual AWS CLI cleanup fallback?"; then
      log "Manual fallback declined; exiting"
      exit 1
    fi

    manual_cleanup_path
  fi

  post_teardown_verification
  log "Teardown sequence complete"
}

main "$@"
