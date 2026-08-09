provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = {
      Project   = var.project
      Stack     = "persistent"
      ManagedBy = "terraform"
    }
  }
}

provider "mongodbatlas" {
  public_key  = var.mongodbatlas_public_key
  private_key = var.mongodbatlas_private_key
}

provider "github" {
  owner = var.github_owner
  token = var.github_token != "" ? var.github_token : null
}
