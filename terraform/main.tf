terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_dynamodb_table" "expense_tracker_data" {
  name         = "ExpenseTrackerData"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.expense_tracker_data.name
  description = "The name of the DynamoDB Single-Table"
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.expense_tracker_data.arn
  description = "The ARN of the DynamoDB Single-Table"
}
