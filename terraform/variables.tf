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

variable "google_client_id" {
  type        = string
  default     = "230057110188-uju5dg9caco861t3bmqjc3qvbtdcuck5.apps.googleusercontent.com"
  description = "Google OAuth client ID accepted by HTTP and WebSocket APIs"
}
