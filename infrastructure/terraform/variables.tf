variable "project" {
  type    = string
  default = "ghb"
}

variable "env" {
  type        = string
  description = "dev | staging | prod"
  default     = "prod"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "az_count" {
  type    = number
  default = 3
}

variable "domain_name" {
  type    = string
  default = "api.galaxyhealthbridge.dev"
}

variable "api_image" {
  type        = string
  description = "ghcr image:tag for the API"
  default     = "ghcr.io/galaxy-health-bridge/api:latest"
}

variable "worker_image" {
  type    = string
  default = "ghcr.io/galaxy-health-bridge/worker:latest"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 50
}

variable "ecs_api_cpu"    { type = number, default = 512 }
variable "ecs_api_memory" { type = number, default = 1024 }
variable "ecs_api_count"  { type = number, default = 3 }
variable "ecs_worker_count" { type = number, default = 2 }

variable "jwt_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret holding JWT_SECRET"
}

variable "encryption_key_arn" {
  type = string
}
