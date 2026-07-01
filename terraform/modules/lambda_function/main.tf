data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "s3_access" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.source_bucket_arn}/*"]
  }
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${var.destination_bucket_arn}/*"]
  }
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "s3_access" {
  name   = "${var.function_name}-s3"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.s3_access.json
}

resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_layer_version" "pillow" {
  filename                 = var.pillow_layer_path
  layer_name               = "${var.function_name}-pillow"
  compatible_runtimes      = ["python3.11"]
  compatible_architectures = ["x86_64"]
  source_code_hash         = filebase64sha256(var.pillow_layer_path)
}

resource "aws_lambda_function" "this" {
  filename                       = var.handler_zip_path
  function_name                  = var.function_name
  role                           = aws_iam_role.lambda.arn
  handler                        = "handler.lambda_handler"
  runtime                        = "python3.11"
  architectures                  = ["x86_64"]
  timeout                        = var.timeout
  memory_size                    = var.memory_size
  reserved_concurrent_executions = var.reserved_concurrent_executions
  source_code_hash               = filebase64sha256(var.handler_zip_path)
  layers                         = [aws_lambda_layer_version.pillow.arn]
  tags                           = var.tags

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DEST_BUCKET = var.destination_bucket_id
    }
  }
}

resource "aws_lambda_alias" "production" {
  name             = "production"
  function_name    = aws_lambda_function.this.function_name
  function_version = "$LATEST"

  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  qualifier     = aws_lambda_alias.production.name
  principal     = "s3.amazonaws.com"
  source_arn    = var.source_bucket_arn
}

resource "aws_s3_bucket_notification" "source" {
  bucket = var.source_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_alias.production.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3]
}