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

resource "aws_budgets_budget" "free_tier_zero_budget" {
  name              = "Zero-Spend-Free-Tier-Budget-${var.environment}"
  budget_type       = "COST"
  limit_amount      = "0.01"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-01-01_00:00"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email_address]
  }
}

resource "aws_apigatewayv2_api" "backend_api" {
  name          = "expense-tracker-api-${var.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.backend_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_sns_topic" "gmail_ingestion_webhook" {
  name = "gmail-ingestion-webhook-${var.environment}"

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

resource "aws_sns_topic" "budget_alerts_topic" {
  name = "budget-spending-alerts-${var.environment}"

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

resource "aws_cloudwatch_event_rule" "gmail_push_event_rule" {
  name        = "gmail-push-event-rule-${var.environment}"
  description = "EventBridge rule to capture real-time Gmail push notification webhooks"

  event_pattern = jsonencode({
    source      = ["custom.gmail.push"]
    detail-type = ["GmailNotification"]
  })

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

resource "aws_cloudwatch_event_target" "gmail_push_event_target" {
  rule      = aws_cloudwatch_event_rule.gmail_push_event_rule.name
  target_id = "SendToGmailSnsTopic"
  arn       = aws_sns_topic.gmail_ingestion_webhook.arn
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.expense_tracker_data.name
  description = "The name of the DynamoDB Single-Table"
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.expense_tracker_data.arn
  description = "The ARN of the DynamoDB Single-Table"
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_api.backend_api.api_endpoint
  description = "The live HTTP API Gateway URL for the backend Lambda service"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.gmail_ingestion_webhook.arn
  description = "The ARN of the Gmail Ingestion SNS Push Webhook Topic"
}

output "budget_alerts_topic_arn" {
  value       = aws_sns_topic.budget_alerts_topic.arn
  description = "The ARN of the Budget Spending Threshold Alerts SNS Topic"
}

output "eventbridge_rule_arn" {
  value       = aws_cloudwatch_event_rule.gmail_push_event_rule.arn
  description = "The ARN of the Gmail EventBridge Push Notification Rule"
}
