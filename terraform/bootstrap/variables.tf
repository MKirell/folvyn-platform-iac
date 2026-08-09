variable "aws_region" {
  description = "Region holding the state and backup buckets."
  type        = string
  default     = "eu-west-3"
}

variable "aws_profile" {
  description = "Local AWS CLI profile Terraform authenticates with."
  type        = string
  default     = "mkirell"
}
