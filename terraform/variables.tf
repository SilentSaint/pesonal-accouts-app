variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS Region for deployment"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment"
}

variable "alert_email_address" {
  type        = string
  description = "Email address for $0 AWS Free Tier budget notifications (Must be provided by user)"
}
