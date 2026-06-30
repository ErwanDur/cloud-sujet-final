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
  default = "./pillow.zip"
}

variable "handler_zip_path" {
  type    = string
  default = "./handler.zip"
}

variable "timeout" {
  type        = number
  default     = 30
  description = "Lambda execution timeout in seconds (3s default is too short for image conversion)"
}

variable "memory_size" {
  type        = number
  default     = 256
  description = "Lambda memory in MB (more memory also means more CPU, speeding up Pillow conversion)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
