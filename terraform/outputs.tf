output "source_bucket" {
  value = module.bucket_source.bucket_id
}

output "destination_bucket" {
  value = module.bucket_dest.bucket_id
}

output "lambda_function_name" {
  value = module.lambda.function_name
}
