variable "account_id" {}

variable "stream_name" {}

variable "transform_lambda_arn" {}

variable "target_s3_bucket_arn" {}

variable "region" {
  default = "eu-west-1"
}
