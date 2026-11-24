#!/usr/bin/env python3
"""Exercise native moved-address planning against mock-applied legacy VPC state.

Requires Terraform >=1.12 for shared test state. No AWS calls are made. Mock
providers do not implement real AWS replacement planning; inspect the customer's
native saved plan before apply.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TF = os.environ.get("TERRAFORM_BIN", "terraform")

with tempfile.TemporaryDirectory(prefix="single-nat-upgrade-") as tmp:
    work = Path(tmp)
    for name, source in (
        ("legacy", ROOT / "tests/fixtures/legacy_single_nat_vpc"),
        ("candidate", ROOT / "modules/vpc"),
    ):
        shutil.copytree(source, work / name, ignore=shutil.ignore_patterns(".terraform", ".terraform.lock.hcl", "tests"))
    # The committed baseline fixture is the VPC module from public v0.6.0.
    (work / "main.tf").write_text('terraform {\n required_providers {\n aws = { source = "hashicorp/aws", version = ">=5.79, <7.0" }\n }\n}\n')
    (work / "tests").mkdir()
    (work / "tests/upgrade.tftest.hcl").write_text('''
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { zone_ids = ["usw2-az1", "usw2-az2"] }
  }
  mock_resource "aws_vpc" {
    defaults = { id = "vpc-0123456789abcdef0", main_route_table_id = "rtb-0123456789abcdef0" }
  }
  mock_resource "aws_subnet" {
    defaults = { id = "subnet-0123456789abcdef0" }
  }
  mock_resource "aws_eip" {
    defaults = { id = "eipalloc-0123456789abcdef0" }
  }
  mock_resource "aws_nat_gateway" {
    defaults = { id = "nat-0123456789abcdef0" }
  }
  mock_resource "aws_internet_gateway" {
    defaults = { id = "igw-0123456789abcdef0" }
  }
  mock_resource "aws_route_table" {
    defaults = { id = "rtb-0123456789abcdef0" }
  }
}
variables {
  base_name = "fixture"
  vpc_cidr = "172.30.0.0/16"
  subnet_cidrs = { usw2-az1 = "172.30.0.0/20", usw2-az2 = "172.30.16.0/20" }
  nat_subnet_cidr = "172.30.255.0/24"
  default_tags = { environment = "test" }
}
run "installed_legacy_vpc" {
  command = apply
  state_key = "legacy-vpc"
  module { source = "./legacy" }
}
run "upgrade_preserves_legacy_vpc" {
  command = plan
  state_key = "legacy-vpc"
  module { source = "./candidate" }
  variables { preserve_legacy_single_nat = true }
}
''')
    env = {**os.environ, "TF_CLI_CONFIG_FILE": os.devnull, "AWS_CONFIG_FILE": os.devnull, "AWS_SHARED_CREDENTIALS_FILE": os.devnull, "AWS_EC2_METADATA_DISABLED": "true", "TF_IN_AUTOMATION": "1", "CHECKPOINT_DISABLE": "1"}
    for args in (["init", "-backend=false", "-input=false", "-no-color"], ["test", "-json", "-verbose"]):
        result = subprocess.run([TF, f"-chdir={work}", *args], env=env, capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
    rows = [json.loads(line) for line in result.stdout.splitlines()]
    plans = [r["test_plan"] for r in rows if "test_plan" in r]
    assert len(plans) == 1, f"Expected one upgrade plan, got {len(plans)}"
    changes = [r for r in plans[0]["resource_changes"] if r["mode"] == "managed"]
    bad = [(r["address"], r["change"]["actions"]) for r in changes if r["change"]["actions"] != ["no-op"]]
    assert not bad, f"Legacy VPC plan changed physical resources: {bad}"
    moves = {r["previous_address"]: r["address"] for r in changes if "previous_address" in r}
    assert moves == {
        "aws_subnet.nat": "aws_subnet.nat[0]",
        "aws_eip.main-nat": "aws_eip.nat[0]",
        "aws_nat_gateway.main": "aws_nat_gateway.main[0]",
        "aws_route.main-nat": "aws_route.main-nat[0]",
        "aws_route_table_association.nat-igw": "aws_route_table_association.nat-igw[0]",
    }, f"Unexpected state migrations: {moves}"
    print(f"PASS: {len(changes)} legacy VPC resources no-op; five state addresses migrated without resource changes (mock providers).")
