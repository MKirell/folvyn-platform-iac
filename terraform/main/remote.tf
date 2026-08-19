data "terraform_remote_state" "persistent" {
  backend = "s3"

  config = {
    bucket  = "${var.legacy_name_prefix}-tfstate-${data.aws_caller_identity.current.account_id}"
    key     = "persistent/terraform.tfstate"
    region  = var.aws_region
    profile = var.aws_profile
  }
}

locals {
  persistent = data.terraform_remote_state.persistent.outputs
}
