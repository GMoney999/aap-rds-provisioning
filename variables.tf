variable "region" { default = "us-west-1" }
variable "db_password" { sensitive = true }
variable "db_username" { default = "aap_admin" }
variable "allowed_cidr" { description = "Your RHEL VM's public/NAT IP in CIDR, e.g. 1.2.3.4/32" }

