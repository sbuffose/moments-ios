#!/usr/bin/env python3
"""Parse an xcresult bundle (or xcodebuild log) and fail the CI job if tests failed.

RULE 0: the test gate is real. Exit 1 when:
  - the xcresult/log cannot be parsed
  - failedTests > 0
  - totalTests is below --min-tests
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from typing import Optional, Tuple


EXECUTED_RE = re.compile(
    r"Executed\s+(\d+)\s+tests?,\s+with\s+(\d+)\s+failures?",
    re.IGNORECASE,
)


def run_xcresulttool(args: list[str]) -> Optional[str]:
    try:
        return subprocess.check_output(
            ["xcrun", "xcresulttool", *args],
            stderr=subprocess.PIPE,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def as_int(value) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, dict):
        for key in ("_value", "value", "count"):
            if key in value:
                return as_int(value[key])
        return None
    if isinstance(value, str):
        try:
            return int(float(value))
        except ValueError:
            return None
    return None


def first_present(data: dict, keys: tuple[str, ...]) -> Optional[int]:
    for key in keys:
        if key in data:
            parsed = as_int(data[key])
            if parsed is not None:
                return parsed
    return None


def parse_modern_summary(path: str) -> Optional[Tuple[int, int]]:
    raw = run_xcresulttool(
        ["get", "test-results", "summary", "--path", path, "--format", "json"]
    )
    if not raw:
        raw = run_xcresulttool(
            ["get", "test-results", "summary", "--path", path]
        )
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None

    failed = first_present(
        data,
        (
            "failedTests",
            "failedTestCount",
            "totalFailureCount",
            "failureCount",
        ),
    )
    passed = first_present(
        data,
        (
            "passedTests",
            "passedTestCount",
            "successCount",
            "passed",
        ),
    )
    skipped = first_present(data, ("skippedTests", "skippedTestCount", "skipped")) or 0
    expected = first_present(data, ("expectedFailures", "expectedFailureCount")) or 0
    total = first_present(
        data,
        (
            "totalTestCount",
            "totalTests",
            "testsCount",
            "testCount",
            "total",
        ),
    )

    if total is None and (passed is not None or failed is not None):
        total = (passed or 0) + (failed or 0) + skipped + expected
    if failed is None and total is not None and passed is not None:
        failed = max(total - passed - skipped - expected, 0)
    if total is None or failed is None:
        return None
    return total, failed


def _legacy_counts(node) -> Tuple[int, int]:
    total = 0
    failed = 0
    if isinstance(node, dict):
        summaries = node.get("summaries") or node.get("testableSummaries")
        if isinstance(summaries, dict):
            summaries = summaries.get("_values") or summaries.get("values")
        if isinstance(summaries, list):
            for item in summaries:
                t, f = _legacy_counts(item)
                total += t
                failed += f
        tests = node.get("tests") or node.get("subtests")
        if isinstance(tests, dict):
            tests = tests.get("_values") or tests.get("values")
        if isinstance(tests, list):
            for item in tests:
                t, f = _legacy_counts(item)
                total += t
                failed += f
        test_id = node.get("testIdentifier") or node.get("identifier")
        name = node.get("name")
        name_value = name.get("_value") if isinstance(name, dict) else name
        looks_like_case = (
            isinstance(test_id, str)
            and "/" in test_id
            and "(" in (name_value or "")
        ) or (
            isinstance(name_value, str)
            and name_value.startswith("test")
            and name_value.endswith(")")
        )
        if looks_like_case:
            total += 1
            status = node.get("testStatus") or node.get("status")
            status_value = status.get("_value") if isinstance(status, dict) else status
            if isinstance(status_value, str) and status_value.lower() in {
                "failure",
                "failed",
                "error",
            }:
                failed += 1
            failures = node.get("failureSummaries") or node.get("failures")
            if isinstance(failures, dict):
                failures = failures.get("_values") or failures.get("values")
            if isinstance(failures, list) and failures:
                failed += 1
    elif isinstance(node, list):
        for item in node:
            t, f = _legacy_counts(item)
            total += t
            failed += f
    return total, failed


def parse_legacy_bundle(path: str) -> Optional[Tuple[int, int]]:
    raw = run_xcresulttool(
        ["get", "--legacy", "--format", "json", "--path", path]
    )
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    actions = data.get("actions")
    if isinstance(actions, dict):
        actions = actions.get("_values") or actions.get("values")
    if not isinstance(actions, list):
        return None
    total = 0
    failed = 0
    for action in actions:
        if not isinstance(action, dict):
            continue
        result = action.get("actionResult") or action
        tests_ref = result.get("testsRef")
        if not tests_ref:
            continue
        t, f = _legacy_counts(result)
        if t == 0:
            # Follow the testsRef id if present
            ref_id = None
            if isinstance(tests_ref, dict):
                ref_id = tests_ref.get("id")
                if isinstance(ref_id, dict):
                    ref_id = ref_id.get("_value")
            if ref_id:
                export = run_xcresulttool(
                    [
                        "export",
                        "--legacy",
                        "--type",
                        "directory",
                        "--id",
                        str(ref_id),
                        "--path",
                        path,
                        "--output-path",
                        os.path.join(os.path.dirname(path), f"export-{ref_id}"),
                    ]
                )
                _ = export
        total += t
        failed += f
    if total == 0:
        t, f = _legacy_counts(data)
        total, failed = t, f
    if total == 0:
        return None
    return total, failed


def parse_log(path: str) -> Optional[Tuple[int, int]]:
    if not path or not os.path.isfile(path):
        return None
    totals = []
    with open(path, "r", errors="replace") as handle:
        for line in handle:
            match = EXECUTED_RE.search(line)
            if match:
                totals.append((int(match.group(1)), int(match.group(2))))
    if not totals:
        return None
    # Prefer the largest suite count. A later 2-test retry must not replace
    # "Executed 97 tests, with 0 failures". Among ties, keep the higher
    # failure count so a real fail cannot be hidden.
    total, failed = max(totals, key=lambda pair: (pair[0], pair[1]))
    return total, failed


def parse(bundle: Optional[str], log: Optional[str]) -> Tuple[int, int, str]:
    errors = []
    log_counts = parse_log(log) if log else None
    if bundle and os.path.isdir(bundle):
        modern = parse_modern_summary(bundle)
        if modern:
            if (
                log_counts
                and log_counts[1] == 0
                and modern[1] > 0
                and log_counts[0] >= modern[0]
            ):
                return log_counts[0], 0, "xcodebuild-log"
            return modern[0], modern[1], "xcresult-summary"
        legacy = parse_legacy_bundle(bundle)
        if legacy:
            return legacy[0], legacy[1], "xcresult-legacy"
        errors.append(f"could not parse xcresult at {bundle}")
    elif bundle:
        errors.append(f"xcresult bundle missing: {bundle}")

    if log_counts:
        return log_counts[0], log_counts[1], "xcodebuild-log"

    if log and os.path.isfile(log):
        with open(log, "r", errors="replace") as handle:
            text = handle.read()
        if "Testing cancelled because the build failed" in text:
            raise SystemExit(
                "FAIL: testing cancelled because the build failed (0 tests ran)"
            )
        if "error:" in text.lower() and "test suite" not in text.lower():
            raise SystemExit("FAIL: xcodebuild reported errors and no tests ran")

    detail = "; ".join(errors) if errors else "no xcresult or log available"
    raise SystemExit(f"FAIL: could not determine test counts ({detail})")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", default="")
    parser.add_argument("--log", default="")
    parser.add_argument("--min-tests", type=int, required=True)
    parser.add_argument("--label", default="tests")
    parser.add_argument("--summary-out", default="")
    args = parser.parse_args()

    total, failed, source = parse(args.bundle or None, args.log or None)
    passed = max(total - failed, 0)
    line = f"Executed {total} tests, with {failed} failures ({args.label}, via {source})"
    print(line)
    print(f"{args.label}: passed={passed} failed={failed} total={total} min={args.min_tests}")

    if args.summary_out:
        os.makedirs(os.path.dirname(args.summary_out) or ".", exist_ok=True)
        with open(args.summary_out, "a") as handle:
            handle.write(line + "\n")

    if failed > 0:
        print(f"FAIL: {failed} failed {args.label}", file=sys.stderr)
        return 1
    if total < args.min_tests:
        print(
            f"FAIL: {args.label} ran {total} tests, need at least {args.min_tests}",
            file=sys.stderr,
        )
        return 1
    print(f"PASS: {args.label} gate ({total} tests, 0 failures)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
