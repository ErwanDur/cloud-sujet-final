variable "function_name" {
  type = string
}

variable "source_bucket_id" {
  type = string
}

variable "source_bucket_arn" {
  type = string
}

variable "destination_bucket_id" {
  type = string
}

variable "destination_bucket_arn" {
  type = string
}

variable "pillow_layer_path" {
  type    = string
  default = "../lambda/layers/pillow.zip"
}

variable "handler_source_dir" {
  type    = string
  default = "../lambda"
}

variable "tags" {
  type    = map(string)
  default = {}
}
