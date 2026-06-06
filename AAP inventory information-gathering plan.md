# Problem statement
The `inventory` file is still a template and cannot be applied safely until concrete host, database, storage, and secret values are collected for this PoC deployment.
## Current state
`inventory` currently contains example hostnames for all component groups and placeholder values for credentials and external database settings. Based on project scope in `aap-rds-context.md` and `RULES.md`, this PoC should focus on `automationgateway`, `automationcontroller`, `automationhub`, and `redis`, with EDA/metrics/lightspeed/MCP out of scope.
## Information to gather
### 1) Topology and host identity
Confirm the final host mapping for `automationgateway`, `automationcontroller`, `automationhub`, and `redis` (single-node vs multi-node for this PoC), and the exact FQDN/IP values to place in inventory.
### 2) Scope alignment in inventory groups
Confirm which groups should be removed or commented out for this run (`execution_nodes`, `automationeda`, `automationmetrics`, and optional lightspeed/MCP blocks) so no unintended components are installed.
### 3) Hub shared storage settings
Decide the real value for `hub_shared_data_path` and whether current mount options are valid for the selected storage approach (local path vs NFS for PoC).
### 4) External PostgreSQL connection data
Gather the final RDS endpoint and admin username from Terraform outputs, then confirm the admin password source. Confirm database names and per-service DB users/passwords for gateway/controller/hub, using one role per database.
### 5) AAP admin/application secrets
Generate and securely store concrete values for `gateway_admin_password`, `controller_admin_password`, and `hub_admin_password`, plus the `*_pg_password` and `postgresql_admin_password` values.
### 6) Installer bundle inputs
Confirm whether `bundle_install=true` remains desired and validate the actual `bundle_dir` path that will exist at install time.
## Source mapping
Terraform outputs provide `rds_endpoint` and `db_username`; PostgreSQL bootstrap steps provide database/user/password values; operator decisions provide host assignments, component scope, shared storage path, and installer/admin secrets.
## Readiness gate
Inventory is ready to finalize only when all placeholders (`<set your own>`, `externaldb.example.org`, and example hostnames) are replaced with validated values, and out-of-scope groups are explicitly excluded for this PoC.
## Execution order
First confirm component scope and host mapping, then collect Terraform DB outputs, then create/verify DB roles and passwords, then generate application admin secrets, then fill and review the inventory in one pass.