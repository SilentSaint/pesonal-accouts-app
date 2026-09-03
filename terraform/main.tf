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
  name                        = "ExpenseTrackerData"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "PK"
  range_key                   = "SK"
  deletion_protection_enabled = var.environment == "prod"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment        = var.environment
    Project            = "AutomaticExpenseTracker"
    DataClassification = "Financial"
    BackupStrategy     = "PITR"
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
    allow_origins = ["https://${aws_cloudfront_distribution.web_distribution.domain_name}"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Gmail-Token"]
    max_age       = 3600
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

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.backend_api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      integrationErr = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_apigatewayv2_authorizer" "google_jwt" {
  api_id           = aws_apigatewayv2_api.backend_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "google-id-token-${var.environment}"

  jwt_configuration {
    audience = [var.google_client_id]
    issuer   = "https://accounts.google.com"
  }
}

# --- Lambda Execution IAM Role & Policy for DynamoDB ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "expense-tracker-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role" "transaction_command_api_role" {
  name = "expense-tracker-transaction-command-api-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "financial_context_api_role" {
  name = "expense-tracker-financial-context-api-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "financial_analytics_api_role" {
  name = "expense-tracker-financial-analytics-api-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "income_source_api_role" {
  name = "expense-tracker-income-source-api-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "transaction_command_worker_role" {
  name = "expense-tracker-transaction-command-worker-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "transaction_command_dlq_role" {
  name = "expense-tracker-transaction-command-dlq-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "transaction_command_api" {
  name              = "/aws/lambda/expense-tracker-transaction-command-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "financial_context_api" {
  name              = "/aws/lambda/expense-tracker-financial-context-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "financial_analytics_api" {
  name              = "/aws/lambda/expense-tracker-financial-analytics-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "income_source_api" {
  name              = "/aws/lambda/expense-tracker-income-source-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend_api_access" {
  name              = "/aws/apigateway/expense-tracker-api-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "transaction_command_worker" {
  name              = "/aws/lambda/expense-tracker-transaction-worker-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "transaction_command_dlq" {
  name              = "/aws/lambda/expense-tracker-transaction-dlq-${var.environment}"
  retention_in_days = 30
}

data "aws_secretsmanager_secret" "gemini_api_key" {
  name = "gemini-key"
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "expense-tracker-lambda-dynamodb-${var.environment}"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.expense_tracker_data.arn,
          "${aws_dynamodb_table.expense_tracker_data.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["execute-api:ManageConnections"]
        Resource = "${aws_apigatewayv2_api.websocket_sync_api.execution_arn}/${aws_apigatewayv2_stage.ws_stage.name}/POST/@connections/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = data.aws_secretsmanager_secret.gemini_api_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "transaction_command_api_policy" {
  name = "expense-tracker-transaction-command-api-${var.environment}"
  role = aws_iam_role.transaction_command_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem", "dynamodb:TransactWriteItems"]
        Resource = aws_dynamodb_table.expense_tracker_data.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.transaction_commands.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          aws_cloudwatch_log_group.transaction_command_api.arn,
          "${aws_cloudwatch_log_group.transaction_command_api.arn}:*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "financial_context_api_policy" {
  name = "expense-tracker-financial-context-api-${var.environment}"
  role = aws_iam_role.financial_context_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.expense_tracker_data.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          aws_cloudwatch_log_group.financial_context_api.arn,
          "${aws_cloudwatch_log_group.financial_context_api.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "income_source_api_policy" {
  name = "expense-tracker-income-source-api-${var.environment}"
  role = aws_iam_role.income_source_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.expense_tracker_data.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          aws_cloudwatch_log_group.income_source_api.arn,
          "${aws_cloudwatch_log_group.income_source_api.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "financial_analytics_api_policy" {
  name = "expense-tracker-financial-analytics-api-${var.environment}"
  role = aws_iam_role.financial_analytics_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = aws_dynamodb_table.expense_tracker_data.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          aws_cloudwatch_log_group.financial_analytics_api.arn,
          "${aws_cloudwatch_log_group.financial_analytics_api.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "transaction_command_worker_policy" {
  name = "expense-tracker-transaction-command-worker-${var.environment}"
  role = aws_iam_role.transaction_command_worker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:TransactWriteItems"
        ]
        Resource = aws_dynamodb_table.expense_tracker_data.arn
      },
      {
        Effect   = "Allow"
        Action   = ["execute-api:ManageConnections"]
        Resource = "${aws_apigatewayv2_api.websocket_sync_api.execution_arn}/${aws_apigatewayv2_stage.ws_stage.name}/POST/@connections/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.transaction_commands.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          aws_cloudwatch_log_group.transaction_command_worker.arn,
          "${aws_cloudwatch_log_group.transaction_command_worker.arn}:*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "transaction_command_dlq_policy" {
  name = "expense-tracker-transaction-command-dlq-${var.environment}"
  role = aws_iam_role.transaction_command_dlq_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.expense_tracker_data.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.transaction_command_dlq.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          aws_cloudwatch_log_group.transaction_command_dlq.arn,
          "${aws_cloudwatch_log_group.transaction_command_dlq.arn}:*"
        ]
      }
    ]
  })
}

# --- Backend REST API Lambda Function ---
resource "aws_lambda_function" "api_handler" {
  function_name    = "expense-tracker-api-handler-${var.environment}"
  filename         = "${path.module}/../backend/lambda/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda/lambda.zip")
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  role             = aws_iam_role.lambda_exec_role.arn
  timeout          = 25
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME                    = aws_dynamodb_table.expense_tracker_data.name
      GEMINI_SECRET_ARN             = data.aws_secretsmanager_secret.gemini_api_key.arn
      WEBSOCKET_MANAGEMENT_ENDPOINT = replace(aws_apigatewayv2_stage.ws_stage.invoke_url, "wss://", "https://")
    }
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

resource "aws_lambda_function" "transaction_command_handler" {
  function_name    = "expense-tracker-transaction-command-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.TransactionCommandHandler::handleRequest"
  role             = aws_iam_role.transaction_command_api_role.arn
  timeout          = 10
  memory_size      = 512

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME                    = aws_dynamodb_table.expense_tracker_data.name
      TRANSACTION_COMMAND_QUEUE_URL = aws_sqs_queue.transaction_commands.url
    }
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
    Module      = "transaction-command"
  }
}

resource "aws_lambda_function" "financial_context_handler" {
  function_name    = "expense-tracker-financial-context-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.FinancialContextHandler::handleRequest"
  role             = aws_iam_role.financial_context_api_role.arn
  timeout          = 10
  memory_size      = 512

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.expense_tracker_data.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
    Module      = "financial-context"
  }
}

resource "aws_lambda_function" "income_source_handler" {
  function_name    = "expense-tracker-income-source-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.IncomeSourceHandler::handleRequest"
  role             = aws_iam_role.income_source_api_role.arn
  timeout          = 10
  memory_size      = 512

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.expense_tracker_data.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
    Module      = "income-source"
  }
}

resource "aws_lambda_function" "financial_analytics_handler" {
  function_name    = "expense-tracker-financial-analytics-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.FinancialAnalyticsHandler::handleRequest"
  role             = aws_iam_role.financial_analytics_api_role.arn
  timeout          = 15
  memory_size      = 512

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.expense_tracker_data.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
    Module      = "financial-analytics"
  }
}

resource "aws_lambda_function" "transaction_command_worker" {
  function_name    = "expense-tracker-transaction-worker-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.TransactionCommandWorker::handleRequest"
  role             = aws_iam_role.transaction_command_worker_role.arn
  timeout          = 10
  memory_size      = 512

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME                    = aws_dynamodb_table.expense_tracker_data.name
      WEBSOCKET_MANAGEMENT_ENDPOINT = replace(aws_apigatewayv2_stage.ws_stage.invoke_url, "wss://", "https://")
    }
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
    Module      = "transaction-command-worker"
  }
}

# This handler consumes only records that exhausted the primary FIFO worker's retries.
resource "aws_lambda_function" "transaction_command_dlq" {
  function_name    = "expense-tracker-transaction-dlq-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.TransactionCommandDlqHandler::handleRequest"
  role             = aws_iam_role.transaction_command_dlq_role.arn
  timeout          = 10
  memory_size      = 512

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.expense_tracker_data.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
    Module      = "transaction-command-dlq"
  }
}

resource "aws_sqs_queue" "transaction_command_dlq" {
  name                      = "expense-tracker-transaction-commands-dlq-${var.environment}.fifo"
  fifo_queue                = true
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

resource "aws_sqs_queue" "transaction_commands" {
  name                        = "expense-tracker-transaction-commands-${var.environment}.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  visibility_timeout_seconds  = 60
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.transaction_command_dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

resource "aws_lambda_event_source_mapping" "transaction_command_worker" {
  event_source_arn = aws_sqs_queue.transaction_commands.arn
  function_name    = aws_lambda_function.transaction_command_worker.arn
  batch_size       = 1
  depends_on       = [aws_iam_role_policy.transaction_command_worker_policy]

  scaling_config {
    maximum_concurrency = 5
  }
}

resource "aws_lambda_event_source_mapping" "transaction_command_dlq" {
  event_source_arn = aws_sqs_queue.transaction_command_dlq.arn
  function_name    = aws_lambda_function.transaction_command_dlq.arn
  batch_size       = 1
  depends_on       = [aws_iam_role_policy.transaction_command_dlq_policy]
}

resource "aws_cloudwatch_metric_alarm" "transaction_command_dlq_messages" {
  alarm_name          = "expense-tracker-transaction-command-dlq-${var.environment}"
  alarm_description   = "Transaction commands reached the FIFO dead-letter queue"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.budget_alerts_topic.arn]

  dimensions = {
    QueueName = aws_sqs_queue.transaction_command_dlq.name
  }
}

resource "aws_cloudwatch_metric_alarm" "transaction_command_worker_throttles" {
  alarm_name          = "expense-tracker-transaction-command-worker-throttles-${var.environment}"
  alarm_description   = "Transaction command worker was throttled"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.budget_alerts_topic.arn]

  dimensions = {
    FunctionName = aws_lambda_function.transaction_command_worker.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "ingestion_failures" {
  alarm_name          = "expense-tracker-ingestion-failures-${var.environment}"
  alarm_description   = "The API Lambda handling Gmail ingestion returned unhandled failures"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.budget_alerts_topic.arn]

  dimensions = {
    FunctionName = aws_lambda_function.api_handler.function_name
  }
}

resource "aws_cloudwatch_log_metric_filter" "authentication_rejections" {
  name           = "expense-tracker-authentication-rejections-${var.environment}"
  log_group_name = aws_cloudwatch_log_group.backend_api_access.name
  pattern        = "{ ($.status = 401) || ($.status = 403) }"

  metric_transformation {
    name          = "AuthenticationRejections"
    namespace     = "ExpenseTracker/Operational"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "authentication_failures" {
  alarm_name          = "expense-tracker-authentication-failures-${var.environment}"
  alarm_description   = "API Gateway rejected five or more requests for authentication or authorization in five minutes"
  namespace           = "ExpenseTracker/Operational"
  metric_name         = aws_cloudwatch_log_metric_filter.authentication_rejections.metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.budget_alerts_topic.arn]
}

resource "aws_cloudwatch_metric_alarm" "reminder_delivery_failures" {
  alarm_name          = "expense-tracker-reminder-delivery-failures-${var.environment}"
  alarm_description   = "Reminder delivery adapter reported a failed delivery"
  namespace           = "ExpenseTracker/Operational"
  metric_name         = "ReminderDeliveryFailures"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.budget_alerts_topic.arn]
}

# --- API Gateway Lambda Integration & Route ---
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.backend_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_handler.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "transaction_command_integration" {
  api_id                 = aws_apigatewayv2_api.backend_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.transaction_command_handler.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "financial_context_integration" {
  api_id                 = aws_apigatewayv2_api.backend_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.financial_context_handler.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "financial_analytics_integration" {
  api_id                 = aws_apigatewayv2_api.backend_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.financial_analytics_handler.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "income_source_integration" {
  api_id                 = aws_apigatewayv2_api.backend_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.income_source_handler.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api_proxy_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "api_root_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "ANY /"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "transaction_command_health_route" {
  api_id    = aws_apigatewayv2_api.backend_api.id
  route_key = "GET /v2/health"
  target    = "integrations/${aws_apigatewayv2_integration.transaction_command_integration.id}"
}

resource "aws_apigatewayv2_route" "api_health_route" {
  api_id    = aws_apigatewayv2_api.backend_api.id
  route_key = "GET /api/health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "api_preflight_route" {
  api_id    = aws_apigatewayv2_api.backend_api.id
  route_key = "OPTIONS /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "transaction_command_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "POST /v2/transactions"
  target             = "integrations/${aws_apigatewayv2_integration.transaction_command_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "financial_context_list_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "GET /v2/financial-context"
  target             = "integrations/${aws_apigatewayv2_integration.financial_context_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "financial_analytics_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "GET /v2/analytics"
  target             = "integrations/${aws_apigatewayv2_integration.financial_analytics_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "financial_analytics_evidence_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "GET /v2/analytics/evidence"
  target             = "integrations/${aws_apigatewayv2_integration.financial_analytics_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "financial_context_eligible_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "GET /v2/financial-context/eligible"
  target             = "integrations/${aws_apigatewayv2_integration.financial_context_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "financial_context_create_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "POST /v2/financial-context"
  target             = "integrations/${aws_apigatewayv2_integration.financial_context_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "financial_context_update_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "PUT /v2/financial-context/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.financial_context_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "financial_context_deactivate_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "POST /v2/financial-context/{id}/deactivate"
  target             = "integrations/${aws_apigatewayv2_integration.financial_context_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "financial_context_delete_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "DELETE /v2/financial-context/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.financial_context_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "income_source_list_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "GET /v2/income-sources"
  target             = "integrations/${aws_apigatewayv2_integration.income_source_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "income_source_create_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "POST /v2/income-sources"
  target             = "integrations/${aws_apigatewayv2_integration.income_source_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "income_source_effective_dates_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "PUT /v2/income-sources/{id}/effective-dates"
  target             = "integrations/${aws_apigatewayv2_integration.income_source_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "income_suggestion_confirm_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "POST /v2/income-sources/{id}/suggestion/confirm"
  target             = "integrations/${aws_apigatewayv2_integration.income_source_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "income_suggestion_reject_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "POST /v2/income-sources/{id}/suggestion/reject"
  target             = "integrations/${aws_apigatewayv2_integration.income_source_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "income_summary_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "GET /v2/income-summary"
  target             = "integrations/${aws_apigatewayv2_integration.income_source_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "transaction_command_status_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "GET /v2/transactions/{id}/status"
  target             = "integrations/${aws_apigatewayv2_integration.transaction_command_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "vendor_rule_learning_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "PUT /v2/transactions/{id}/category"
  target             = "integrations/${aws_apigatewayv2_integration.transaction_command_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "reconciliation_review_queue_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "GET /v2/reconciliation/review-queue"
  target             = "integrations/${aws_apigatewayv2_integration.transaction_command_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "reconciliation_merge_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "POST /v2/reconciliation/{id}/merge"
  target             = "integrations/${aws_apigatewayv2_integration.transaction_command_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "reconciliation_confirm_route" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "PUT /v2/reconciliation/{id}/confirm"
  target             = "integrations/${aws_apigatewayv2_integration.transaction_command_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_lambda_permission" "apigw_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_transaction_command_permission" {
  statement_id  = "AllowAPIGatewayInvokeTransactionCommand"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transaction_command_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_financial_context_permission" {
  statement_id  = "AllowAPIGatewayInvokeFinancialContext"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.financial_context_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_financial_analytics_permission" {
  statement_id  = "AllowAPIGatewayInvokeFinancialAnalytics"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.financial_analytics_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_income_source_permission" {
  statement_id  = "AllowAPIGatewayInvokeIncomeSource"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.income_source_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend_api.execution_arn}/*/*"
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

resource "aws_sns_topic_subscription" "operational_alert_email" {
  topic_arn = aws_sns_topic.budget_alerts_topic.arn
  protocol  = "email"
  endpoint  = var.alert_email_address
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

resource "aws_apigatewayv2_api" "websocket_sync_api" {
  name                       = "expense-tracker-ws-sync-${var.environment}"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

resource "aws_cloudwatch_log_group" "websocket_sync" {
  name              = "/aws/lambda/expense-tracker-websocket-sync-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "websocket_authorizer" {
  name              = "/aws/lambda/expense-tracker-websocket-authorizer-${var.environment}"
  retention_in_days = 30
}

resource "aws_iam_role" "websocket_sync_role" {
  name = "expense-tracker-websocket-sync-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "websocket_authorizer_role" {
  name = "expense-tracker-websocket-authorizer-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "websocket_sync_policy" {
  name = "expense-tracker-websocket-sync-${var.environment}"
  role = aws_iam_role.websocket_sync_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.expense_tracker_data.arn
      },
      {
        Effect   = "Allow"
        Action   = ["execute-api:ManageConnections"]
        Resource = "${aws_apigatewayv2_api.websocket_sync_api.execution_arn}/${aws_apigatewayv2_stage.ws_stage.name}/POST/@connections/*"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          aws_cloudwatch_log_group.websocket_sync.arn,
          "${aws_cloudwatch_log_group.websocket_sync.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "websocket_authorizer_policy" {
  name = "expense-tracker-websocket-authorizer-${var.environment}"
  role = aws_iam_role.websocket_authorizer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = [
        aws_cloudwatch_log_group.websocket_authorizer.arn,
        "${aws_cloudwatch_log_group.websocket_authorizer.arn}:*"
      ]
    }]
  })
}

resource "aws_lambda_function" "websocket_sync_handler" {
  function_name    = "expense-tracker-websocket-sync-${var.environment}"
  filename         = "${path.module}/../backend/lambda/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda/lambda.zip")
  runtime          = "nodejs20.x"
  handler          = "websocket_sync.handler"
  role             = aws_iam_role.websocket_sync_role.arn
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME                    = aws_dynamodb_table.expense_tracker_data.name
      WEBSOCKET_MANAGEMENT_ENDPOINT = replace(aws_apigatewayv2_stage.ws_stage.invoke_url, "wss://", "https://")
    }
  }
}

resource "aws_lambda_function" "websocket_authorizer" {
  function_name    = "expense-tracker-websocket-authorizer-${var.environment}"
  filename         = "${path.module}/../backend/lambda/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda/lambda.zip")
  runtime          = "nodejs20.x"
  handler          = "websocket_authorizer.handler"
  role             = aws_iam_role.websocket_authorizer_role.arn
  timeout          = 5
  memory_size      = 128

  environment {
    variables = {
      GOOGLE_CLIENT_ID = var.google_client_id
    }
  }
}

resource "aws_apigatewayv2_stage" "ws_stage" {
  api_id      = aws_apigatewayv2_api.websocket_sync_api.id
  name        = var.environment
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "websocket_sync" {
  api_id             = aws_apigatewayv2_api.websocket_sync_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.websocket_sync_handler.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "websocket_authorizer" {
  api_id             = aws_apigatewayv2_api.websocket_sync_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.websocket_authorizer.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_authorizer" "websocket_google_identity" {
  api_id           = aws_apigatewayv2_api.websocket_sync_api.id
  name             = "google-id-token-${var.environment}"
  authorizer_type  = "REQUEST"
  authorizer_uri   = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.websocket_authorizer.arn}/invocations"
  identity_sources = ["route.request.querystring.token"]
}

resource "aws_apigatewayv2_route" "websocket_connect" {
  api_id             = aws_apigatewayv2_api.websocket_sync_api.id
  route_key          = "$connect"
  target             = "integrations/${aws_apigatewayv2_integration.websocket_sync.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.websocket_google_identity.id
}

resource "aws_apigatewayv2_route" "websocket_disconnect" {
  api_id    = aws_apigatewayv2_api.websocket_sync_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_sync.id}"
}

resource "aws_apigatewayv2_route" "websocket_default" {
  api_id    = aws_apigatewayv2_api.websocket_sync_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_sync.id}"
}

resource "aws_lambda_permission" "websocket_sync_invoke" {
  statement_id  = "AllowWebSocketGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_sync_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_sync_api.execution_arn}/*"
}

resource "aws_lambda_permission" "websocket_authorizer_invoke" {
  statement_id  = "AllowWebSocketAuthorizerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_sync_api.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.websocket_google_identity.id}"
}

# --- S3 Static Hosting Bucket for Flutter Web Application ---
resource "aws_s3_bucket" "web_app_bucket" {
  bucket_prefix = "expense-tracker-web-${var.environment}-"
  force_destroy = true

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

resource "aws_s3_bucket_public_access_block" "web_app_pab" {
  bucket = aws_s3_bucket.web_app_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- CloudFront Origin Access Control (OAC) ---
resource "aws_cloudfront_origin_access_control" "web_oac" {
  name                              = "expense-tracker-web-oac-${var.environment}"
  description                       = "OAC for Flutter Web App S3 Bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --- CloudFront CDN Distribution ---
resource "aws_cloudfront_distribution" "web_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.web_app_bucket.bucket_regional_domain_name
    origin_id                = "S3-Flutter-WebApp"
    origin_access_control_id = aws_cloudfront_origin_access_control.web_oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Flutter-WebApp"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  # SPA Routing: Redirect 403/404 to index.html with 200 OK
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.environment
    Project     = "AutomaticExpenseTracker"
  }
}

# --- S3 Bucket Policy for CloudFront OAC Read Access ---
resource "aws_s3_bucket_policy" "web_app_policy" {
  bucket = aws_s3_bucket.web_app_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.web_app_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.web_distribution.arn
          }
        }
      }
    ]
  })
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

output "websocket_sync_url" {
  value       = aws_apigatewayv2_stage.ws_stage.invoke_url
  description = "The live WebSocket API URL for multi-device real-time sync"
}

output "cloudfront_web_url" {
  value       = "https://${aws_cloudfront_distribution.web_distribution.domain_name}"
  description = "The live public HTTPS CloudFront URL for the Flutter Web Application"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.web_distribution.id
  description = "The CloudFront distribution ID for deployment invalidations"
}

output "s3_web_bucket_name" {
  value       = aws_s3_bucket.web_app_bucket.id
  description = "The S3 bucket hosting the Flutter Web static assets"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.gmail_ingestion_webhook.arn
  description = "The ARN of the Gmail Ingestion SNS Push Webhook Topic"
}

output "budget_alerts_topic_arn" {
  value       = aws_sns_topic.budget_alerts_topic.arn
  description = "The ARN of the Budget Spending Threshold Alerts SNS Topic"
}

output "operational_alerts_topic_arn" {
  value       = aws_sns_topic.budget_alerts_topic.arn
  description = "The SNS topic receiving production operational alarms"
}

output "eventbridge_rule_arn" {
  value       = aws_cloudwatch_event_rule.gmail_push_event_rule.arn
  description = "The ARN of the Gmail EventBridge Push Notification Rule"
}
