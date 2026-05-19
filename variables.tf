variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "ci-lab"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}