variable "aws_region" {
  type        = string
  default     = "ap-south-2"
  description = "AWS Region for deployment (Hyderabad, India)"
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
