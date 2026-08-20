data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_assume" {
  for_each = local.environments

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = flatten([
        for repo in local.github_repositories : [
          "repo:${var.github_owner}/${repo}:environment:${each.key}",
          "repo:${var.github_owner}@*/${repo}@*:environment:${each.key}",
        ]
      ])
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:repository"
      values = flatten([
        for repo in local.github_repositories : [
          "${var.github_owner}/${repo}",
          "${var.github_owner}@*/${repo}@*",
        ]
      ])
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  for_each = local.environments

  name                 = "${var.project}-github-deploy-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.github_assume[each.key].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_deploy" {
  for_each = local.environments

  statement {
    sid    = "PushImages"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "RollLambda"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:PublishVersion",
    ]
    resources = ["arn:aws:lambda:*:${data.aws_caller_identity.current.account_id}:function:${var.project}-*-${each.key}"]
  }

  statement {
    sid    = "PublishSite"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:PutObjectAcl",
    ]
    resources = [
      "arn:aws:s3:::${var.project}-spa-${each.key}-*",
      "arn:aws:s3:::${var.project}-spa-${each.key}-*/*",
    ]
  }

  statement {
    sid       = "InvalidateEdge"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation", "cloudfront:ListDistributions"]
    resources = ["*"]
  }

  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${var.legacy_name_prefix}-tfstate-*",
      "arn:aws:s3:::${var.legacy_name_prefix}-tfstate-*/env/${each.key}/*",
    ]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  for_each = local.environments

  name   = "${var.project}-github-deploy-${each.key}"
  role   = aws_iam_role.github_deploy[each.key].id
  policy = data.aws_iam_policy_document.github_deploy[each.key].json
}

resource "aws_iam_role_policy_attachment" "github_terraform_plan" {
  for_each = var.github_terraform_plan ? local.environments : {}

  role       = aws_iam_role.github_deploy[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_terraform_apply" {
  for_each = local.environments

  statement {
    sid    = "Certificates"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:DeleteCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Edge"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:CreateResponseHeadersPolicy",
      "cloudfront:UpdateResponseHeadersPolicy",
      "cloudfront:DeleteResponseHeadersPolicy",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DnsRecordsInProjectZoneOnly"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${aws_route53_zone.main.zone_id}"]
  }

  statement {
    sid    = "Compute"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:UpdateFunctionConfiguration",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = ["arn:aws:lambda:*:${data.aws_caller_identity.current.account_id}:function:${var.project}-*-${each.key}"]
  }

  statement {
    sid       = "HttpApi"
    effect    = "Allow"
    actions   = ["apigateway:POST", "apigateway:PATCH", "apigateway:PUT", "apigateway:DELETE"]
    resources = ["arn:aws:apigateway:*::/apis*", "arn:aws:apigateway:*::/domainnames*", "arn:aws:apigateway:*::/tags*"]
  }

  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = ["arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/*${var.project}-*-${each.key}*"]
  }

  statement {
    sid    = "SiteBuckets"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketTagging",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:aws:s3:::${var.project}-spa-${each.key}-*",
      "arn:aws:s3:::${var.project}-spa-${each.key}-*/*",
      "arn:aws:s3:::${var.project}-assets-${each.key}-*",
      "arn:aws:s3:::${var.project}-assets-${each.key}-*/*",
    ]
  }

  statement {
    sid    = "HostedUiDomainOnly"
    effect = "Allow"
    actions = [
      "cognito-idp:CreateUserPoolDomain",
      "cognito-idp:DeleteUserPoolDomain",
      "cognito-idp:UpdateUserPoolDomain",
    ]
    resources = [aws_cognito_user_pool.main.arn]
  }

  statement {
    sid    = "LambdaExecutionRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*-${each.key}-lambda"]
  }

  statement {
    sid       = "LambdaExecutionRolePolicyAttachment"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*-${each.key}-lambda"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
    }
  }
}

resource "aws_iam_role_policy" "github_terraform_apply" {
  for_each = toset([for env in var.environments : env if contains(var.github_terraform_apply_environments, env)])

  name   = "${var.project}-github-terraform-apply-${each.key}"
  role   = aws_iam_role.github_deploy[each.key].id
  policy = data.aws_iam_policy_document.github_terraform_apply[each.key].json
}
