#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "Expected output to contain: $needle"
  fi
}

test_dry_run_prints_expected_steps() {
  [[ -x "$ROOT_DIR/teardown.sh" ]] || fail "Expected executable teardown.sh at repo root"

  local output
  output="$("$ROOT_DIR/teardown.sh" --dry-run --yes 2>&1)"

  assert_contains "$output" "terraform plan -destroy"
  assert_contains "$output" "terraform destroy"
  assert_contains "$output" "aws rds describe-db-snapshots"
}

main() {
  test_dry_run_prints_expected_steps
  printf 'PASS: teardown helper tests\n'
}

main "$@"
