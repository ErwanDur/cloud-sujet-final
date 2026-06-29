data "aws_caller_identity" "current" {}

locals {
  prefix = var.project_prefix
}

module "bucket_source" {
  source      = "./modules/s3_bucket"
  bucket_name = "${local.prefix}-source-${data.aws_caller_identity.current.account_id}"
}

module "bucket_dest" {
  source      = "./modules/s3_bucket"
  bucket_name = "${local.prefix}-dest-${data.aws_caller_identity.current.account_id}"
}

module "lambda" {
  source                 = "./modules/lambda_function"
  function_name          = "${local.prefix}-image-converter"
  source_bucket_id       = module.bucket_source.bucket_id
  source_bucket_arn      = module.bucket_source.bucket_arn
  destination_bucket_id  = module.bucket_dest.bucket_id
  destination_bucket_arn = module.bucket_dest.bucket_arn
}
