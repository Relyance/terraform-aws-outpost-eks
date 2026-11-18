# One root owns these AWS resources. The shared Molokai project/pool has one
# separate platform owner; do not instantiate that platform stack per region.
terraform {
  required_version = "~> 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.79, < 7.0" }
  }
}
provider "aws" {
  alias  = "west"
  region = "us-west-2"
}
provider "aws" {
  alias  = "east"
  region = "us-east-1"
}
module "west" {
  source                                 = "Relyance-Ext/sierra/aws"
  version                                = "0.10.1"
  providers                              = { aws = aws.west }
  create_vpc_and_eks                     = false
  existing_eks_cluster_name              = var.west_cluster_name
  require_existing_eks_cluster_auto_mode = false
  base_name                              = "Relyance_InHost_West"
  s3_bucket_suffix                       = "-west"
  deployment_id                          = "west"
  route_revision                         = 1
  additional_service_account_namespaces  = ["inhost"]
  assumable_account_ids                  = var.scan_account_ids
  byok_secret_arn_patterns               = var.west_secret_arn_patterns
  byok_secret_write_back                 = false
}
module "east" {
  source                                 = "Relyance-Ext/sierra/aws"
  version                                = "0.10.1"
  providers                              = { aws = aws.east }
  create_vpc_and_eks                     = false
  existing_eks_cluster_name              = var.east_cluster_name
  require_existing_eks_cluster_auto_mode = false
  base_name                              = "Relyance_InHost_East"
  s3_bucket_suffix                       = "-east"
  deployment_id                          = "east"
  route_revision                         = 1
  additional_service_account_namespaces  = ["inhost"]
  assumable_account_ids                  = var.scan_account_ids
  byok_secret_arn_patterns               = var.east_secret_arn_patterns
  byok_secret_write_back                 = false
}
variable "west_cluster_name" { type = string }
variable "east_cluster_name" { type = string }
variable "scan_account_ids" { type = list(string) }
# Supply exact reviewed regional/account-scoped patterns; no secret values.
variable "west_secret_arn_patterns" { type = list(string) }
variable "east_secret_arn_patterns" { type = list(string) }
output "regional_customer_facts" {
  value = { west = module.west.provisioning_facts, east = module.east.provisioning_facts }
}
