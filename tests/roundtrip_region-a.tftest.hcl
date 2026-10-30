# No AWS/Kubernetes/HTTP calls: these plans exercise both EKS branches with mocks.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-west-2" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/deployer" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:user/deployer" }
  }
  mock_data "aws_availability_zones" {
    defaults = { zone_ids = ["usw2-az1", "usw2-az2"] }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      name                      = "fixture-cluster"
      endpoint                  = "https://example.invalid"
      identity                  = [{ oidc = [{ issuer = "https://oidc.eks.us-west-2.amazonaws.com/id/REGIONA" }] }]
      certificate_authority     = [{ data = "Zm9v" }]
      compute_config            = [{ enabled = true }]
      kubernetes_network_config = [{ elastic_load_balancing = [{ enabled = true }] }]
      storage_config            = [{ block_storage = [{ enabled = true }] }]
    }
  }
  mock_data "aws_eks_addon" {
    defaults = { addon_version = "v1.3.4-eksbuild.1" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/fixture-reader" }
  }
}
mock_provider "http" {}
mock_provider "random" {}
mock_provider "kubernetes" {}

variables {
  create_vpc_and_eks                     = false
  existing_eks_cluster_name              = "fixture-cluster"
  require_existing_eks_cluster_auto_mode = false
  require_existing_eks_cluster_addons    = false
  assumable_account_ids                  = ["444455556666"]
  deployment_id                          = "region-a"
  route_revision                         = 1
  inventory_uri                          = "s3://relyance-findings-123456789012-region-a/inventory/v1"
  outbox_uri                             = "s3://relyance-work-123456789012-region-a/outbox/v1"
  base_name                              = "Scanner-region-a"
  s3_bucket_suffix                       = "-region-a"
}
run "customer_roundtrip" {
  command = apply
  override_resource {
    target = aws_iam_role.main
    values = { arn = "arn:aws:iam::123456789012:role/Scanner-region-a" }
  }
  override_resource {
    target = aws_iam_role.reader
    values = { arn = "arn:aws:iam::123456789012:role/Reader-region-a" }
  }
  override_resource {
    target = module.work_bucket.aws_s3_bucket.bucket
    values = { id = "relyance-work-123456789012-region-a" }
  }
  override_resource {
    target = module.findings_bucket.aws_s3_bucket.bucket
    values = { id = "relyance-findings-123456789012-region-a" }
  }
  assert {
    condition     = output.provisioning_facts.deployment_id == "region-a" && output.provisioning_facts.aws_region == "us-west-2" && output.provisioning_facts.inventory_uri == "s3://relyance-findings-123456789012-region-a/inventory/v1" && output.provisioning_facts.outbox_uri == "s3://relyance-work-123456789012-region-a/outbox/v1"
    error_message = "Roundtrip facts must bind actual regional provider facts."
  }
}
run "reject_incomplete_dp_roots" {
  command = plan
  variables { outbox_uri = null }
  expect_failures = [output.provisioning_facts]
}
run "reject_foreign_dp_bucket" {
  command = plan
  variables { inventory_uri = "s3://foreign-bucket/inventory/v1" }
  expect_failures = [output.provisioning_facts]
}
run "reject_ancestor_dp_prefix" {
  command = plan
  variables { outbox_uri = "s3://relyance-findings-123456789012-region-a/inventory/v1/outbox" }
  expect_failures = [output.provisioning_facts]
}
run "reject_noncanonical_dp_prefix" {
  command = plan
  variables { inventory_uri = "s3://relyance-findings-123456789012-region-a/inventory/../v1" }
  expect_failures = [var.inventory_uri]
}
run "customer_gai_roundtrip" {
  command = apply
  variables {
    inventory_uri = null
    outbox_uri    = null
  }
  override_resource {
    target = aws_iam_role.main
    values = { arn = "arn:aws:iam::123456789012:role/Scanner-region-a" }
  }
  override_resource {
    target = aws_iam_role.reader
    values = { arn = "arn:aws:iam::123456789012:role/Reader-region-a" }
  }
  override_resource {
    target = module.work_bucket.aws_s3_bucket.bucket
    values = { id = "relyance-work-123456789012-region-a" }
  }
  override_resource {
    target = module.findings_bucket.aws_s3_bucket.bucket
    values = { id = "relyance-findings-123456789012-region-a" }
  }
  assert {
    condition     = output.provisioning_facts.inventory_uri == null && output.provisioning_facts.outbox_uri == null
    error_message = "GAI-only facts must preserve null DP roots."
  }
}
run "reject_inventory_root_in_private_work_bucket" {
  command = plan
  variables { inventory_uri = "s3://relyance-work-123456789012-region-a/inventory/v1" }
  expect_failures = [output.provisioning_facts]
}
