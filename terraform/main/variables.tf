variable "prerender_enabled" {
  description = "Create the publish-time renderer. Its code is deployed by the portfolio front end's own pipeline, so Terraform creates the function and never updates its bundle."
  type        = bool
  default     = true
}

variable "prerender_memory_mb" {
  description = "Rasterising a card is the expensive part; below 512 MB it is slow rather than cheap."
  type        = number
  default     = 1024
}

variable "prerender_timeout_seconds" {
  description = "One portfolio, one card per locale. Generous, because it never blocks a request."
  type        = number
  default     = 60
}

variable "access_allowed_emails" {
  description = <<-EOT
    Per environment, the email addresses allowed to sign in to it. An environment
    absent from the map, or mapped to an empty list, lets anyone sign in — which is
    what prod wants once sign-up opens. dev lists the people meant to be testing it.

    The values are personal email addresses, so the map lives in secrets.auto.tfvars,
    which is gitignored, and never in an environments/*.tfvars file. It is keyed by
    environment because that one file is loaded by every environment's apply.

    It gates authentication, not the public surface: a published dev portfolio is
    still readable by anyone with the URL, and is noindex for that reason.
  EOT
  type        = map(list(string))
  default     = {}
  sensitive   = true
}

variable "environment" {
  description = "Which deployed environment this state describes. Every resource name and every tag carries it."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod. local deploys nothing."
  }
}

variable "aws_region" {
  description = "Region for everything except the CloudFront and Cognito certificates."
  type        = string
  default     = "eu-west-3"
}

variable "aws_profile" {
  description = "Local AWS CLI profile Terraform authenticates with."
  type        = string
  default     = "mkirell"
}

variable "project" {
  description = "Name prefix applied to every resource."
  type        = string
  default     = "folvyn"
}

variable "domain_name" {
  description = "Apex domain. Subdomains are derived from it."
  type        = string
  default     = "mkirell.com"
}

variable "legacy_name_prefix" {
  description = "Name prefix of the resources that predate the Folvyn rename and cannot be renamed without being replaced. Here it names only the state bucket this stack reads persistent's outputs from. Kept in step with the same variable in persistent."
  type        = string
  default     = "mkirell"
}

variable "portfolio_prefix" {
  description = <<-EOT
    First path segment every portfolio lives under. The three application
    repositories hold the same value as PORTFOLIO_PREFIX.
  EOT
  type        = string
  default     = "fol"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.portfolio_prefix))
    error_message = "portfolio_prefix must be lowercase alphanumerics with no slashes."
  }
}

variable "compute_mode" {
  description = "Where the microservice runs. The same ECR image serves both."
  type        = string
  default     = "lambda"

  validation {
    condition     = contains(["lambda", "fargate"], var.compute_mode)
    error_message = "compute_mode must be either \"lambda\" or \"fargate\"."
  }
}

variable "dns_validated" {
  description = <<-EOT
    Phase gate. Leave false for the first apply: certificates are requested and
    their validation records printed. Set true once those records resolve, and
    the second apply attaches the custom domains.
  EOT
  type        = bool
  default     = false
}

variable "app_image_tag" {
  description = <<-EOT
    Tag of the microservice image in ECR. Leave empty on the first apply, before
    any image exists; compute is skipped until it is set.
  EOT
  type        = string
  default     = ""
}

variable "app_log_retention_days" {
  description = "CloudWatch log retention. Kept short to stay inside the free tier."
  type        = number
  default     = 14
}

variable "lambda_memory_mb" {
  description = "Lambda memory. CPU scales with it, so this is also the speed dial."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout. API Gateway caps the response at 30s regardless."
  type        = number
  default     = 30
}

variable "mongodbatlas_org_id" {
  description = "Atlas organisation that will own the project."
  type        = string
}

variable "mongodbatlas_public_key" {
  description = "Atlas programmatic API key, public half."
  type        = string
  sensitive   = true
}

variable "mongodbatlas_private_key" {
  description = "Atlas programmatic API key, private half."
  type        = string
  sensitive   = true
}

variable "atlas_region" {
  description = "Atlas region. M0 is not offered in every AWS region; eu-west-3 is not one of them."
  type        = string
  default     = "EU_WEST_1"
}

variable "google_client_id" {
  description = "Google OAuth client id, federated by Cognito."
  type        = string
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth client secret, held by Cognito and never by the app."
  type        = string
  default     = ""
  sensitive   = true
}

variable "fargate_cpu" {
  description = "Task CPU units when compute_mode is fargate."
  type        = number
  default     = 256
}

variable "fargate_memory" {
  description = "Task memory in MiB when compute_mode is fargate."
  type        = number
  default     = 512
}

variable "fargate_desired_count" {
  description = "Running tasks. Zero keeps the definition without paying for compute."
  type        = number
  default     = 1
}

variable "github_token" {
  description = "PAT with repo and Actions write scope. Empty leaves the workflow variables unmanaged."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_owner" {
  type    = string
  default = "MKirell"
}

variable "manage_github_ci" {
  description = <<-EOT
    Whether this stack writes the deploy workflows' environment variables. It needs a token
    with the Environments permission; a token without it cannot create them and every apply
    fails on a 403 while the rest of the environment is already converged.

    The values are per environment, so they are environment variables rather than repository
    ones — two environments cannot share one repository variable without overwriting each
    other on every apply.
  EOT
  type        = bool
  default     = true
}
