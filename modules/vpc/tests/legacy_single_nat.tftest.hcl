mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { zone_ids = ["usw2-az1", "usw2-az2"] }
  }
}

variables {
  base_name       = "fixture"
  vpc_cidr        = "172.30.0.0/16"
  subnet_cidrs    = { usw2-az1 = "172.30.0.0/20", usw2-az2 = "172.30.16.0/20" }
  nat_subnet_cidr = "172.30.255.0/24"
  default_tags    = {}
}

run "preserve_existing_single_nat" {
  command = plan
  variables {
    preserve_legacy_single_nat = true
  }
  assert {
    condition     = length(aws_subnet.nat) == 1 && length(aws_nat_gateway.main) == 1 && length(aws_eip.nat) == 1
    error_message = "Legacy installations must retain exactly one NAT subnet, gateway and EIP."
  }
  assert {
    condition     = aws_subnet.nat[0].cidr_block == "172.30.255.0/24"
    error_message = "The existing NAT subnet must retain its full CIDR to avoid replacement."
  }
}

run "legacy_routes_use_existing_main_table" {
  command = plan
  variables {
    preserve_legacy_single_nat = true
  }
  assert {
    condition     = length(aws_route.main-nat) == 1 && length(aws_route_table.private) == 0 && length(aws_route_table_association.private) == 0
    error_message = "Legacy routing must retain the main-table route without new private tables or associations."
  }
}

run "legacy_minimum_subnet_remains_supported" {
  command = plan
  variables {
    preserve_legacy_single_nat = true
    nat_subnet_cidr            = "172.30.255.0/28"
  }
  assert {
    condition     = aws_subnet.nat[0].cidr_block == "172.30.255.0/28"
    error_message = "A previously valid /28 NAT subnet must remain unsplit."
  }
}

run "default_retains_two_nat_gateways" {
  command = plan
  assert {
    condition     = length(aws_subnet.nat) == 2 && length(aws_nat_gateway.main) == 2 && length(aws_eip.nat) == 2
    error_message = "New installations must retain the two-NAT default."
  }
  assert {
    condition     = aws_subnet.nat[0].cidr_block == "172.30.255.0/25" && aws_subnet.nat[1].cidr_block == "172.30.255.128/25"
    error_message = "New installations must retain the existing split-subnet layout."
  }
}
