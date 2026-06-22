locals {
  name        = "${var.project}-${var.env}"
  common_tags = {
    Project    = "galaxy-health-bridge"
    Env        = var.env
    ManagedBy  = "terraform"
    Component  = "platform"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_password" "db" {
  length  = 32
  special = false
}
