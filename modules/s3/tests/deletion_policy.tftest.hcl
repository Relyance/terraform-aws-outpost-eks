# Real local policy-document evaluation; every cloud resource is overridden.
# Apply/teardown manipulate only virtual resources, with fake credentials.
provider "aws" {
  region                      = "us-west-2"
  access_key                  = "fixture"
  secret_key                  = "fixture"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
override_resource {
  target = aws_s3_bucket.bucket
  values = { id = "findings-fixture", arn = "arn:aws:s3:::findings-fixture" }
}
override_resource {
  target = aws_s3_bucket_policy.bucket
}
override_resource {
  target = aws_s3_bucket_lifecycle_configuration.bucket
}
override_resource {
  target = aws_s3_bucket_versioning.bucket
}
override_resource {
  target = aws_s3_bucket_server_side_encryption_configuration.bucket
}
override_resource {
  target = aws_s3_bucket_public_access_block.bucket
}
variables {
  name                   = "findings-fixture"
  kms_key_arn            = "arn:aws:kms:us-west-2:000000000123:key/fixture"
  expiration_days        = 180
  full_access_principals = ["arn:aws:iam::000000000123:role/scanner"]
  rw_access_principals   = []
  ro_access_principals   = ["arn:aws:iam::000000000123:role/reader"]
  wo_access_principals   = []
}
run "findings_full_access_deletes_reader_remains_ro" {
  command = apply
  assert {
    condition = length([
      for statement in jsondecode(aws_s3_bucket_policy.bucket.policy).Statement : statement
      if try(
        statement.Effect == "Allow" &&
        statement.Principal.AWS == "arn:aws:iam::000000000123:role/scanner" &&
        alltrue([for action in ["s3:DeleteObject", "s3:DeleteObjectVersion"] : contains(statement.Action, action)]) &&
        toset(statement.Resource) == toset(["arn:aws:s3:::findings-fixture", "arn:aws:s3:::findings-fixture/*"]),
        false,
      )
    ]) == 1
    error_message = "The scanner must be able to delete objects and versions in the dedicated findings bucket."
  }
  assert {
    condition = toset(flatten([
      for statement in jsondecode(aws_s3_bucket_policy.bucket.policy).Statement : statement.Action
      if try(statement.Effect == "Allow" && statement.Principal.AWS == "arn:aws:iam::000000000123:role/reader", false)
    ])) == toset(["s3:ListBucket", "s3:GetObject", "s3:GetObjectVersion"])
    error_message = "The hosted reader must retain its read-only findings access."
  }
}

run "denies_insecure_transport" {
  command = plan
  assert {
    condition = anytrue([
      for statement in jsondecode(aws_s3_bucket_policy.bucket.policy).Statement :
      try(
        statement.Effect == "Deny" &&
        statement.Principal == "*" &&
        statement.Action == "s3:*" &&
        toset(statement.Resource) == toset(["arn:aws:s3:::findings-fixture", "arn:aws:s3:::findings-fixture/*"]) &&
        tostring(statement.Condition.Bool["aws:SecureTransport"]) == "false",
        false,
      )
    ])
    error_message = "The bucket policy must deny plaintext requests to bucket and object APIs."
  }
}
