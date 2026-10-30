#!/usr/bin/env python3
"""Compare actual native mock resource plans to a fetched base, without state.

Every address and planned known/unknown resource attribute must agree. This is
source compatibility proof; it is not a plan against any customer's Terraform
state and cannot qualify actual remote no-replacement behavior.
"""

import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT


def plan(terraform, root):
    result = subprocess.run(
        [
            terraform,
            f"-chdir={root}",
            "test",
            "-filter=tests/legacy_snapshot.tftest.hcl",
            "-json",
            "-verbose",
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    entries = [json.loads(line) for line in result.stdout.splitlines()]
    plans = [item["test_plan"] for item in entries if "test_plan" in item]
    assert len(plans) == 2, "Expected legacy existing-cluster and create-cluster plans"
    return [
        {
            row["address"]: {
                key: row[key]
                for key in ("mode", "type", "name", "provider_name", "change")
            }
            for row in native["resource_changes"]
        }
        for native in plans
    ]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref", required=True)
    parser.add_argument(
        "--terraform", default=os.environ.get("TERRAFORM_BIN", "terraform")
    )
    args = parser.parse_args()
    candidate = plan(args.terraform, ROOT)
    with tempfile.TemporaryDirectory(prefix="inhost-legacy-source-") as directory:
        archive = subprocess.run(
            ["git", "-C", str(REPO), "archive", args.baseline_ref],
            capture_output=True,
            check=True,
        ).stdout
        with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
            stream.extractall(directory, filter="data")
        baseline = Path(directory)
        (baseline / "tests/legacy_snapshot.tftest.hcl").write_text(
            (ROOT / "tests/legacy_snapshot.tftest.hcl").read_text()
        )
        (baseline / ".terraform").symlink_to(
            ROOT / ".terraform", target_is_directory=True
        )
        (baseline / ".terraform.lock.hcl").write_bytes(
            (ROOT / ".terraform.lock.hcl").read_bytes()
        )
        original = plan(args.terraform, baseline)
    assert candidate == original, (
        "Legacy resource addresses or planned authority changed relative to base"
    )
    print(
        f"Exact legacy native resource plan agrees with {args.baseline_ref}: {sum(len(plan) for plan in candidate)} addresses across both cluster modes"
    )
