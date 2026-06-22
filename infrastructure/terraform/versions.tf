terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.70" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
  backend "s3" {}  # configured via -backend-config
}

provider "aws" {
  region = var.region
  default_tags { tags = local.common_tags }
}
