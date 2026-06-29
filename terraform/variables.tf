variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

variable "role_arn" {
  type    = string
  default = "arn:aws:iam::738563260931:role/role_etudiants"
}

variable "project_prefix" {
  type    = string
  default = "ynov"
}
