

variable "aws_region" {
  type    = string
  default = "us-east-1"
}


variable "root_domain" {
  description = "Root domain name"
  type        = string
}

variable "subdomain" {
  description = "Subdomain prefix"
  type        = string
  default     = "www"
}

locals {
  full_domain = "${var.subdomain}.${var.root_domain}"
}