output "default_tags" {
  description = "Tags to be applied to all resources"
  value       = local.default_tags
}

output "reader_external_id" {
  description = "External ID required to be passed for the STS assume-role"
  value       = random_uuid.reader_external_id.result
}

output "oidc_issuer" {
  description = "OIDC URL to be provided to Relyance for cross-cloud access"
  value       = local.eks_cluster_oidc_issuer
}

output "enable_auto_mode_node_tags" {
  description = "Is there support for auto mode nodes with custom tags?"
  value       = var.enable_auto_mode_node_tags
}

output "aws_account_id" {
  description = "AWS account ID where this module is deployed"
  value       = local.account_id
}

output "cluster_created_by_module" {
  description = "Whether the EKS cluster was created by this module (true) or an existing cluster was used (false)"
  value       = var.create_vpc_and_eks
}

output "eks_cluster_auto_mode" {
  description = "Whether the EKS cluster is running in auto mode. Always true for module-created clusters."
  value       = var.create_vpc_and_eks ? true : module.existing_eks[0].is_auto_mode
}

output "byok_secret_write_back" {
  description = "Whether the scanner role may write refreshed OAuth tokens back to BYOK secrets (var.byok_secret_write_back). Pass it to the deployment: Helm value byokSecretWriteBack, or env var SECRET_REF_WRITE_BACK (\"true\"/\"false\") in the kustomize package. The two must match: with false here and write-back on in the deployment, each write-back is denied and logged."
  value       = var.byok_secret_write_back
}

output "findings_object_deletion" {
  description = "Applied deletion capability for this dedicated findings bucket. Pass unchanged to deployment provisioning. Allows ordinary object deletion and permanent deletion of every version throughout this bucket for the scanner role. Older modules without this output keep deployment deletion gates off."
  value = {
    enabled    = true
    account_id = local.account_id
    bucket     = module.findings_bucket.id
  }
}

output "provisioning_facts" {
  description = "Nonsecret facts from the actual installation. Add reviewed deployment ID/revision in the platform handoff; reader_external_id remains a separate custody channel."
  precondition {
    condition = var.inventory_uri == null ? var.outbox_uri == null : try(
      var.deployment_id != null && var.outbox_uri != null &&
      split("/", var.inventory_uri)[2] == module.findings_bucket.id &&
      contains([module.work_bucket.id, module.findings_bucket.id], split("/", var.outbox_uri)[2]) &&
      var.inventory_uri != var.outbox_uri &&
    !startswith(var.inventory_uri, "${var.outbox_uri}/") && !startswith(var.outbox_uri, "${var.inventory_uri}/"), false)
    error_message = "DP roots need a complete disjoint pair, inventory in the reader-authorized findings bucket, outbox in an existing regional bucket, and explicit deployment identity."
  }
  value = var.deployment_id == null ? null : {
    schema_version   = 1
    deployment_id    = var.deployment_id
    route_revision   = var.route_revision
    aws_account_id   = local.account_id
    aws_partition    = data.aws_partition.current.partition
    aws_region       = data.aws_region.current.name
    oidc_issuer      = local.eks_cluster_oidc_issuer
    work_uri         = "s3://${module.work_bucket.id}"
    findings_uri     = "s3://${module.findings_bucket.id}"
    inventory_uri    = var.inventory_uri
    outbox_uri       = var.outbox_uri
    scanner_role_arn = aws_iam_role.main.arn
    reader_role_arn  = aws_iam_role.reader.arn
    bucket_authorities = {
      for name in [module.work_bucket.id, module.findings_bucket.id] : name => {
        aws_account_id = local.account_id
        aws_region     = data.aws_region.current.name
      }
    }
  }
}
