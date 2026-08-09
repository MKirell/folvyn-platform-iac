data "terraform_remote_state" "persistent" {
  backend = "s3"

  config = {
    bucket  = "mkirell-tfstate-848906241169"
    key     = "persistent/terraform.tfstate"
    region  = "eu-west-3"
    profile = var.aws_profile
  }
}

locals {
  persistent = data.terraform_remote_state.persistent.outputs
}
