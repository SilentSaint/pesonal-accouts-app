# FIE-05 proactive insight event pipeline. ExpenseTrackerData must enable
# NEW_IMAGE streams in main.tf before the stream mapping can be applied.

resource "aws_iam_role" "proactive_insight_enqueuer_role" {
  name = "expense-tracker-proactive-insight-enqueuer-${var.environment}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role" "proactive_insight_worker_role" {
  name = "expense-tracker-proactive-insight-worker-${var.environment}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role" "proactive_insight_scheduler_role" {
  name = "expense-tracker-proactive-insight-scheduler-${var.environment}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role" "proactive_insight_api_role" {
  name = "expense-tracker-proactive-insight-api-${var.environment}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_cloudwatch_log_group" "proactive_insight_enqueuer" {
  name              = "/aws/lambda/expense-tracker-proactive-insight-enqueuer-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "proactive_insight_worker" {
  name              = "/aws/lambda/expense-tracker-proactive-insight-worker-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "proactive_insight_scheduler" {
  name              = "/aws/lambda/expense-tracker-proactive-insight-scheduler-${var.environment}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "proactive_insight_api" {
  name              = "/aws/lambda/expense-tracker-proactive-insight-api-${var.environment}"
  retention_in_days = 30
}

resource "aws_sqs_queue" "proactive_insight_dlq" {
  name                      = "expense-tracker-proactive-insights-dlq-${var.environment}"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "proactive_insight_refresh" {
  name                       = "expense-tracker-proactive-insight-refresh-${var.environment}"
  visibility_timeout_seconds = 120
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.proactive_insight_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_iam_role_policy" "proactive_insight_enqueuer" {
  name = "expense-tracker-proactive-insight-enqueuer-${var.environment}"
  role = aws_iam_role.proactive_insight_enqueuer_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
        Resource = [aws_dynamodb_table.expense_tracker_data.arn, aws_dynamodb_table.expense_tracker_data.stream_arn]
      },
      { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.proactive_insight_refresh.arn },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.proactive_insight_enqueuer.arn}:*"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "proactive_insight_worker" {
  name = "expense-tracker-proactive-insight-worker-${var.environment}"
  role = aws_iam_role.proactive_insight_worker_role.id
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
        Action   = ["execute-api:ManageConnections"]
        Resource = "${aws_apigatewayv2_api.websocket_sync_api.execution_arn}/${aws_apigatewayv2_stage.ws_stage.name}/POST/@connections/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.proactive_insight_refresh.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.proactive_insight_worker.arn}:*"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "proactive_insight_scheduler" {
  name = "expense-tracker-proactive-insight-scheduler-${var.environment}"
  role = aws_iam_role.proactive_insight_scheduler_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:Query"], Resource = aws_dynamodb_table.expense_tracker_data.arn },
      { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.proactive_insight_refresh.arn },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.proactive_insight_scheduler.arn}:*"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "proactive_insight_api" {
  name = "expense-tracker-proactive-insight-api-${var.environment}"
  role = aws_iam_role.proactive_insight_api_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:UpdateItem"], Resource = aws_dynamodb_table.expense_tracker_data.arn },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.proactive_insight_api.arn}:*"]
      }
    ]
  })
}

resource "aws_lambda_function" "proactive_insight_enqueuer" {
  function_name    = "expense-tracker-proactive-insight-enqueuer-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.CanonicalTransactionInsightEnqueuer::handleRequest"
  role             = aws_iam_role.proactive_insight_enqueuer_role.arn
  timeout          = 30
  memory_size      = 512
  environment {
    variables = {
      TABLE_NAME                = aws_dynamodb_table.expense_tracker_data.name
      INSIGHT_REFRESH_QUEUE_URL = aws_sqs_queue.proactive_insight_refresh.url
    }
  }
}

resource "aws_lambda_function" "proactive_insight_worker" {
  function_name    = "expense-tracker-proactive-insight-worker-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.ProactiveInsightWorker::handleRequest"
  role             = aws_iam_role.proactive_insight_worker_role.arn
  timeout          = 60
  memory_size      = 1024
  environment {
    variables = {
      TABLE_NAME                    = aws_dynamodb_table.expense_tracker_data.name
      WEBSOCKET_MANAGEMENT_ENDPOINT = replace(aws_apigatewayv2_stage.ws_stage.invoke_url, "wss://", "https://")
    }
  }
}

resource "aws_lambda_function" "proactive_insight_scheduler" {
  function_name    = "expense-tracker-proactive-insight-scheduler-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.DailyProactiveInsightScheduler::handleRequest"
  role             = aws_iam_role.proactive_insight_scheduler_role.arn
  timeout          = 30
  memory_size      = 512
  environment {
    variables = {
      TABLE_NAME                = aws_dynamodb_table.expense_tracker_data.name
      INSIGHT_REFRESH_QUEUE_URL = aws_sqs_queue.proactive_insight_refresh.url
    }
  }
}

resource "aws_lambda_function" "proactive_insight_api" {
  function_name    = "expense-tracker-proactive-insight-api-${var.environment}"
  filename         = "${path.module}/../backend/build/lambda/transaction-command-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/build/lambda/transaction-command-lambda.zip")
  runtime          = "java21"
  handler          = "com.automaticexpense.tracker.infrastructure.api.ProactiveInsightHandler::handleRequest"
  role             = aws_iam_role.proactive_insight_api_role.arn
  timeout          = 15
  memory_size      = 512
  environment {
    variables = {
      TABLE_NAME                    = aws_dynamodb_table.expense_tracker_data.name
      WEBSOCKET_MANAGEMENT_ENDPOINT = replace(aws_apigatewayv2_stage.ws_stage.invoke_url, "wss://", "https://")
    }
  }
}

resource "aws_lambda_event_source_mapping" "proactive_insight_transaction_stream" {
  event_source_arn  = aws_dynamodb_table.expense_tracker_data.stream_arn
  function_name     = aws_lambda_function.proactive_insight_enqueuer.arn
  starting_position = "LATEST"
  batch_size        = 10

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
        dynamodb = {
          NewImage = {
            entityType = { S = ["TRANSACTION"] }
            PK         = { S = [{ prefix = "USER#" }] }
            SK         = { S = [{ prefix = "TXN#" }] }
          }
        }
      })
    }
  }

  depends_on = [aws_iam_role_policy.proactive_insight_enqueuer]
}

resource "aws_lambda_event_source_mapping" "proactive_insight_worker" {
  event_source_arn = aws_sqs_queue.proactive_insight_refresh.arn
  function_name    = aws_lambda_function.proactive_insight_worker.arn
  batch_size       = 1
  depends_on       = [aws_iam_role_policy.proactive_insight_worker]
}

resource "aws_cloudwatch_event_rule" "proactive_insight_daily_refresh" {
  name                = "expense-tracker-proactive-insight-daily-${var.environment}"
  schedule_expression = "cron(0 1 * * ? *)"
}

resource "aws_cloudwatch_event_target" "proactive_insight_daily_refresh" {
  rule = aws_cloudwatch_event_rule.proactive_insight_daily_refresh.name
  arn  = aws_lambda_function.proactive_insight_scheduler.arn
}

resource "aws_lambda_permission" "proactive_insight_scheduler_eventbridge" {
  statement_id  = "AllowEventBridgeDailyInsightRefresh"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proactive_insight_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.proactive_insight_daily_refresh.arn
}

resource "aws_apigatewayv2_integration" "proactive_insight" {
  api_id                 = aws_apigatewayv2_api.backend_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.proactive_insight_api.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "proactive_insight_list" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "GET /v2/insights"
  target             = "integrations/${aws_apigatewayv2_integration.proactive_insight.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_apigatewayv2_route" "proactive_insight_dismiss" {
  api_id             = aws_apigatewayv2_api.backend_api.id
  route_key          = "POST /v2/insights/{id}/dismiss"
  target             = "integrations/${aws_apigatewayv2_integration.proactive_insight.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.google_jwt.id
}

resource "aws_lambda_permission" "proactive_insight_api_gateway" {
  statement_id  = "AllowApiGatewayInsightRoutes"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proactive_insight_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.backend_api.execution_arn}/*/*"
}

resource "aws_cloudwatch_metric_alarm" "proactive_insight_dlq_messages" {
  alarm_name          = "expense-tracker-proactive-insight-dlq-${var.environment}"
  alarm_description   = "Proactive insight refresh work reached its dead-letter queue"
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
    QueueName = aws_sqs_queue.proactive_insight_dlq.name
  }
}
