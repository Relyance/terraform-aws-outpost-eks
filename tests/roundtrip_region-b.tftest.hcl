# No AWS/Kubernetes/HTTP calls: these plans exercise both EKS branches with mocks.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
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
      identity                  = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/REGIONB" }] }]
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
  deployment_id                          = "region-b"
  route_revision                         = 1
  base_name                              = "Scanner-region-b"
  s3_bucket_suffix                       = "-region-b"
}
run "customer_roundtrip" {
  command = apply
  override_resource {
    target = aws_iam_role.main
    values = { arn = "arn:aws:iam::123456789012:role/Scanner-region-b" }
  }
  override_resource {
    target = aws_iam_role.reader
    values = { arn = "arn:aws:iam::123456789012:role/Reader-region-b" }
  }
  override_resource {
    target = module.work_bucket.aws_s3_bucket.bucket
    values = { id = "relyance-work-123456789012-region-b" }
  }
  override_resource {
    target = module.findings_bucket.aws_s3_bucket.bucket
    values = { id = "relyance-findings-123456789012-region-b" }
  }
  assert {
    condition     = output.provisioning_facts.deployment_id == "region-b" && output.provisioning_facts.aws_region == "us-east-1"
    error_message = "Roundtrip facts must bind actual regional provider facts."
  }
}
