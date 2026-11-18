# No AWS/Kubernetes/HTTP calls: these plans exercise both EKS branches with mocks.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { name = "us-west-2" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333", arn = "arn:aws:iam::111122223333:user/deployer" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::111122223333:user/deployer" }
  }
  mock_data "aws_availability_zones" {
    defaults = { zone_ids = ["usw2-az1", "usw2-az2"] }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      name                      = "fixture-cluster"
      endpoint                  = "https://example.invalid"
      identity                  = [{ oidc = [{ issuer = "https://oidc.example.invalid" }] }]
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
    defaults = { arn = "arn:aws:iam::111122223333:role/fixture-reader" }
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
}
run "legacy_snapshot" { command = plan }

run "legacy_create_cluster_snapshot" {
  command = plan
  variables {
    create_vpc_and_eks = true
    vpc_cidr           = "172.30.0.0/16"
    service_cidr       = null
    subnet_cidrs       = { usw2-az1 = "172.30.0.0/20", usw2-az2 = "172.30.16.0/20" }
    nat_subnet_cidr    = "172.30.255.0/24"
    eks_kubectl_admins = {
      primary   = format("arn:aws:iam::%s:role/fixture-primary", var.assumable_account_ids[0])
      secondary = format("arn:aws:iam::%s:role/fixture-secondary", var.assumable_account_ids[0])
    }
  }
}
