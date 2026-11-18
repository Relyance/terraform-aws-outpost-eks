resource "aws_kms_key" "main" {
  description             = "KMS symmetric key for Relyance environment"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = local.default_tags
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.base_name}"
  target_key_id = aws_kms_key_policy.main.key_id
}

resource "aws_kms_key_policy" "main" {
  key_id = aws_kms_key.main.id
  policy = local.restrict_kms_key_use ? jsonencode(local.restricted_kms_key_policy) : data.aws_iam_policy_document.main_kms_key[0].json

  lifecycle {
    precondition {
      condition     = !local.restrict_kms_key_use || contains(var.kms_key_administrator_role_arns, data.aws_iam_session_context.current.issuer_arn)
      error_message = "Include the Terraform AWS provider role in kms_key_administrator_role_arns to retain access to update the key policy."
    }

    precondition {
      condition     = !local.restrict_kms_key_use ? true : alltrue([for grant in local.s3_kms_grants : length(setintersection(var.kms_key_administrator_role_arns, toset(grant.principals))) == 0])
      error_message = "KMS key administrator roles must be separate from the Sierra workload roles."
    }
  }
}

data "aws_iam_policy_document" "main_kms_key" {
  count = local.restrict_kms_key_use ? 0 : 1

  # Regular use
  statement {
    principals {
      type = "AWS"
      identifiers = concat(
        [aws_iam_role.main.arn],
        var.create_vpc_and_eks ? module.eks[0].node_role_arns : [],
      )
    }
    resources = [aws_kms_key.main.arn]
    actions = [
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext"
    ]
  }

  statement {
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.reader.arn]
    }
    resources = [aws_kms_key.main.arn]
    actions   = ["kms:Decrypt"]
  }

  # Admins need to have ability to manage the key going forward
  statement {
    principals {
      type = "AWS"
      identifiers = [
        data.aws_iam_session_context.current.issuer_arn,
        "arn:aws:iam::${local.account_id}:root",
      ]
    }
    resources = [aws_kms_key.main.arn]
    actions = [
      "kms:*",
    ]
  }
}

locals {
  restrict_kms_key_use = length(var.kms_key_administrator_role_arns) > 0

  s3_kms_grants = merge({
    ScannerS3KeyUse = {
      principals = [aws_iam_role.main.arn]
      actions    = ["kms:Decrypt", "kms:GenerateDataKey"]
      buckets    = var.code_analysis_enabled ? ["findings", "work", "sci"] : ["findings", "work"]
    }
    ReaderS3KeyUse = {
      principals = [aws_iam_role.reader.arn]
      actions    = ["kms:Decrypt"]
      buckets    = ["findings"]
    }
    }, var.code_analysis_enabled ? {
    SciS3KeyUse = {
      principals = aws_iam_role.sci[*].arn
      actions    = ["kms:Decrypt", "kms:GenerateDataKey"]
      buckets    = ["sci"]
    }
  } : {})

  s3_kms_encryption_contexts = {
    for bucket, name in local.s3_bucket_names : bucket => [
      "arn:${data.aws_partition.current.partition}:s3:::${name}",
      "arn:${data.aws_partition.current.partition}:s3:::${name}/*",
    ]
  }

  restricted_kms_key_policy = {
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid       = "KeyAdministration"
        Effect    = "Allow"
        Principal = { AWS = sort(tolist(var.kms_key_administrator_role_arns)) }
        Resource  = "*"
        Action = [
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:PutKeyPolicy",
          "kms:ListResourceTags",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:GetKeyRotationStatus",
          "kms:EnableKeyRotation",
          "kms:DisableKeyRotation",
          "kms:UpdateKeyDescription",
          "kms:CreateAlias",
          "kms:UpdateAlias",
          "kms:DeleteAlias",
          "kms:EnableKey",
          "kms:DisableKey",
          "kms:ListGrants",
          "kms:RevokeGrant",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
        ]
      }],
      # EKS CreateCluster requires CreateGrant on this key. The EKS API does
      # not support the kms:GrantIsForAWSResource condition on that request.
      var.create_vpc_and_eks ? [{
        Sid       = "CreateEksEncryptionGrant"
        Effect    = "Allow"
        Principal = { AWS = sort(tolist(var.kms_key_administrator_role_arns)) }
        Resource  = "*"
        Action    = ["kms:CreateGrant"]
      }] : [],
      [for sid, grant in local.s3_kms_grants : {
        Sid       = sid
        Effect    = "Allow"
        Principal = { AWS = grant.principals }
        Resource  = "*"
        Action    = grant.actions
        Condition = {
          # KMS uses this service name suffix in every AWS partition.
          StringEquals = { "kms:ViaService" = "s3.${data.aws_region.current.name}.amazonaws.com" }
          StringLike = {
            "kms:EncryptionContext:aws:s3:arn" = flatten([
              for bucket in grant.buckets : local.s3_kms_encryption_contexts[bucket]
            ])
          }
        }
      }]
    )
  }
}
