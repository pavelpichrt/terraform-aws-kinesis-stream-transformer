data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "firehose_log_group" {
  name              = "/aws/firehose/${var.stream_name}"
  retention_in_days = 60

  tags = {
    ENV = var.env
  }
}

resource "aws_s3_bucket" "transformed_records" {
  bucket = "apps-poc-transformed-${var.env}"
  acl    = "private"
}

resource "aws_kinesis_firehose_delivery_stream" "extended_s3_stream" {
  name        = var.stream_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose_role.arn
    bucket_arn          = aws_s3_bucket.transformed_records.arn
    prefix              = "success/!{timestamp:yyyy/MM/dd}/"
    error_output_prefix = "failure/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/"
    buffer_size         = 1
    buffer_interval     = 60

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/firehose/${var.stream_name}"
      log_stream_name = "/aws/firehose/${var.stream_name}/stream"
    }

    processing_configuration {
      enabled = "true"

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${var.transform_lambda_arn}:$LATEST"
        }
      }
    }
  }
}


resource "aws_iam_role" "firehose_role" {
  name = "apps_poc_firehose_role_${var.env}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow", 
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "firehose_policy" {
  name   = "firehose-${var.stream_name}-${var.env}-policy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "glue:GetTable",
                "glue:GetTableVersion",
                "glue:GetTableVersions"
            ],
            "Resource": [
                "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:catalog",
                "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:database/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%",
                "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:table/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads",
                "s3:PutObject"
            ],
            "Resource": [
                "${aws_s3_bucket.transformed_records.arn}",
                "${aws_s3_bucket.transformed_records.arn}/*"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction",
                "lambda:GetFunctionConfiguration"
            ],
            "Resource": "${var.transform_lambda_arn}:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:GenerateDataKey",
                "kms:Decrypt"
            ],
            "Resource": [
                "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%"
            ],
            "Condition": {
                "StringEquals": {
                    "kms:ViaService": "s3.${var.region}.amazonaws.com"
                },
                "StringLike": {
                    "kms:EncryptionContext:aws:s3:arn": [
                        "arn:aws:s3:::%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%/*"
                    ]
                }
            }
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents"
            ],
            "Resource": [
                "${aws_cloudwatch_log_group.firehose_log_group.arn}:*"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:GetShardIterator",
                "kinesis:GetRecords",
                "kinesis:ListShards"
            ],
            "Resource": "arn:aws:kinesis:${var.region}:${data.aws_caller_identity.current.account_id}:stream/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt"
            ],
            "Resource": [
                "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%"
            ],
            "Condition": {
                "StringEquals": {
                    "kms:ViaService": "kinesis.${var.region}.amazonaws.com"
                },
                "StringLike": {
                    "kms:EncryptionContext:aws:kinesis:arn": "arn:aws:kinesis:${var.region}:${data.aws_caller_identity.current.account_id}:stream/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%"
                }
            }
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "apps_lambda_role_policy_attachment" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.firehose_policy.arn
}
