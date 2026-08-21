variable "environments" {
  description = "Deployed environments this shared stack provisions per-environment resources for: one app client, one Atlas project and one deploy role each."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

variable "aws_profile" {
  type    = string
  default = "mkirell"
}

variable "project" {
  type    = string
  default = "folvyn"
}

variable "legacy_name_prefix" {
  description = "Name prefix of the resources that already existed when the project was renamed to Folvyn and cannot be renamed without being replaced: the state and backup buckets, the Atlas cluster and its database user, and the ECR repository. Renaming any of them destroys what it holds. They are renamed for real in Phase 12, each as its own migration."
  type        = string
  default     = "mkirell"
}

variable "domain_name" {
  type    = string
  default = "mkirell.com"
}

variable "mongodbatlas_org_id" {
  type = string
}

variable "mongodbatlas_public_key" {
  type      = string
  sensitive = true
}

variable "mongodbatlas_private_key" {
  type      = string
  sensitive = true
}

variable "atlas_region" {
  type    = string
  default = "EU_WEST_1"
}

variable "google_client_id" {
  type    = string
  default = ""
}

variable "google_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "linkedin_client_id" {
  type    = string
  default = ""
}

variable "linkedin_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "github_owner" {
  type    = string
  default = "MKirell"
}

variable "github_terraform_plan" {
  description = "Let CI run terraform plan. Needs account-wide read to refresh state."
  type        = bool
  default     = true
}

variable "github_terraform_apply_environments" {
  description = "Environments whose CI role may apply the main stack. Grants writes to that environment's resources only; persistent stays out of reach, and prod is left out until an approval gate is trusted more than a branch rule."
  type        = list(string)
  default     = ["dev"]
}

variable "github_prod_reviewer_ids" {
  description = <<-EOT
    Numeric GitHub user ids who must approve a prod deployment. Empty leaves the
    prod environment with no gate, which is only ever right before anyone depends
    on it. They are personal identifiers, so they live in secrets.auto.tfvars.

    Read one with: gh api users/<login> --jq .id
  EOT
  type        = list(number)
  default     = []
}

variable "github_token" {
  description = "PAT with repo and Actions write scope. Empty leaves the workflow variables unmanaged."
  type        = string
  default     = ""
  sensitive   = true
}

variable "platform_operator_usernames" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Cognito usernames that operate the platform. They land in the `platform` group,
    which the API reads from `cognito:groups`, and are never provisioned a portfolio.

    A federated user's name is `<Provider>_<subject>`, and the user only exists after
    that person has signed in once — federation cannot be created ahead of time. On a
    fresh pool, sign in with each operator account, then apply.

    Read them back with:
      aws cognito-idp list-users --user-pool-id <id> \
        --query "Users[].{u:Username,email:Attributes[?Name=='email']|[0].Value}" --output table
  EOT
}

variable "mail_mx_records" {
  description = <<-EOT
    Where mail for the domain is delivered. The default is Google Workspace's
    classic five-host set, which every tenant accepts. Google's newer single
    record, ["1 smtp.google.com"], is equivalent for current tenants.
  EOT
  type        = list(string)
  default = [
    "1 aspmx.l.google.com",
    "5 alt1.aspmx.l.google.com",
    "5 alt2.aspmx.l.google.com",
    "10 alt3.aspmx.l.google.com",
    "10 alt4.aspmx.l.google.com",
  ]
}

variable "mail_spf_record" {
  description = "Who is allowed to send as this domain. One SPF record only, ever."
  type        = string
  default     = "v=spf1 include:_spf.google.com ~all"
}

variable "mail_domain_verifications" {
  description = <<-EOT
    Ownership proofs that must live as TXT records on the apex, alongside SPF.
    Losing these can un-verify the Google Workspace tenant.
  EOT
  type        = list(string)
  default     = ["google-site-verification=flaNPyW18T7wcIvyqBWowVjgV6aRYldtHQS-pVxZyK4"]
}

variable "mail_dmarc_record" {
  description = <<-EOT
    What a receiver should do when SPF or DKIM fails. Google Workspace is the
    only sender, so quarantine is safe: anything failing is not ours. Move to
    p=reject once a few weeks of reports stay clean.
  EOT
  type        = string
  default     = "v=DMARC1; p=quarantine; rua=mailto:admin@mkirell.com; fo=1; adkim=r; aspf=r"
}

variable "mail_dkim_selector" {
  description = "DKIM selector Google publishes the key under. 'google' unless you changed it."
  type        = string
  default     = "google"
}

variable "mail_dkim_record" {
  description = <<-EOT
    The DKIM public key from the Google Admin console, Apps > Google Workspace >
    Gmail > Authenticate email. Empty until you generate it, and the record is
    skipped while it is empty because a wrong key is worse than none.
  EOT
  type        = string
  default     = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwhnQaiOiGwYanIXMTgca5pJGpf/YHUZ2LSbPJzzGt4L4557gzVihNMy7xFtpxInJmB1jj+XY+8n8dpjR6O/kvxtcU/OOr8p6RSQ7wu6b8OKXaeB7mtnypsLPDu2jEOv4omNJqnWg6ZJjb/3QHE8QCJ3qhCMfb/AIn2Ohm+YXV8pgH9AsHhHOwjOO4BN8srNLoujUqflmzNPIluQ3Ga/t5aspob3QBxtiCrq+zjO+1sAGOxR17XKv2TjT6NoYQ2aDL4Xpr6TLGaw3c71BXLwhF7VMbVcYMZ4vn/RmxZcKqCifN/6x64OWhEcnpsfz/zqCWEqUwrvGtHcUFIGt46ROuwIDAQAB"
}
