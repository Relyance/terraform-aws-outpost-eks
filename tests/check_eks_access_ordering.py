#!/usr/bin/env python3
"""Verify EKS access creation order in Terraform's native dependency graph.

Run after local terraform init. The graph command does not refresh state or call
AWS. Resource plan equality is checked separately by check_legacy_plan.py.
"""

import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def assert_access_entry_dependency(graph):
    edges = {}
    for source, target in re.findall(
        r'^\s*"([^"]+)" -> "([^"]+)"', graph, re.MULTILINE
    ):
        edges.setdefault(source, set()).add(target)

    def reaches(source, target):
        pending, seen = [source], set()
        while pending:
            node = pending.pop()
            if node == target:
                return True
            if node not in seen:
                seen.add(node)
                pending.extend(edges.get(node, ()))
        return False

    entry = "[root] module.eks.aws_eks_access_entry.admin (expand)"
    for name in ("admin", "cluster-admin"):
        association = (
            f"[root] module.eks.aws_eks_access_policy_association.{name} (expand)"
        )
        assert reaches(association, entry), (
            f"{name} policy association can run before its EKS access entry"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--terraform", default=os.environ.get("TERRAFORM_BIN", "terraform")
    )
    args = parser.parse_args()
    result = subprocess.run(
        [args.terraform, f"-chdir={ROOT}", "graph", "-type=plan"],
        check=True,
        text=True,
        capture_output=True,
    )
    assert_access_entry_dependency(result.stdout)
    print(
        "Native Terraform graph orders both EKS admin policies after access entry creation"
    )
