locals {
  src_image = "${local.lambda_source_ecr}/${var.lambda_source_image}:${var.lambda_source_image_tag}"
  lambda_source_ecr = "${var.lambda_source_account}.dkr.ecr.us-east-1.amazonaws.com"
  dst_image_ecr = var.lambda_use_ecr_pull_through_cache ? "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/${aws_ecr_pull_through_cache_rule.ecr_public_cache[0].ecr_repository_prefix}/${var.lambda_source_image}" : ""
}

resource "aws_ecr_pull_through_cache_rule" "ecr_public_cache" {
  count = var.lambda_use_ecr_pull_through_cache ? 1 : 0
  ecr_repository_prefix = "autospotting"
  upstream_registry_url = local.lambda_source_ecr
  custom_role_arn = aws_iam_role.autospotting_ecr_pull_role[0].arn
}

resource "aws_iam_role" "autospotting_ecr_pull_role" {
  name = "autospotting-pull-role"
  count = var.lambda_use_ecr_pull_through_cache ? 1 : 0

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pullthroughcache.ecr.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.lambda_source_account}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecr_pull_inline" {
  name = "autospotting-pull-inline-policy"
  count = var.lambda_use_ecr_pull_through_cache ? 1 : 0

  role = aws_iam_role.autospotting_ecr_pull_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchImportUpstreamImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetAuthorizationToken",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetImageCopyStatus",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_ecr_authorization_token" "source" {
  count       = var.lambda_use_public_ecr ? 0 : 1
  registry_id = var.lambda_use_public_ecr ? null : split(".", local.lambda_source_ecr)[0]
  provider    = aws.us-east-1
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}
data "aws_ecrpublic_authorization_token" "source" {
  count    = var.lambda_use_public_ecr ? 1 : 0
  provider = aws.us-east-1
}

data "aws_ecr_authorization_token" "destination" {}
