#!/usr/bin/env bash
# ABOUTME: Checks that every workflow run by both a branch push and its pull request keys its
# ABOUTME: concurrency group on the branch name, so the second run cancels the first instead of doubling it.

set -euo pipefail

WORKFLOWS="${1:-$(cd "$(dirname "$0")/../../.github/workflows" && pwd)}"
# A push run has no head_ref and a ref of refs/heads/<branch>; a pull_request
# run has head_ref <branch> and a ref of refs/pull/<n>/merge. Only this key
# names the branch the same way in both.
BRANCH_KEY='github.head_ref || github.ref_name'

failures=0
checked=0
for file in "$WORKFLOWS"/*.yml; do
    grep -qE '^  push:' "$file" || continue
    grep -qE '^  pull_request:' "$file" || continue
    group="$(grep -E '^  group:' "$file" || true)"
    [[ -n "$group" ]] || continue
    # A group that names the event keeps push and pull_request runs apart on purpose.
    [[ "$group" == *github.event_name* ]] && continue
    checked=$((checked + 1))
    if [[ "$group" != *"$BRANCH_KEY"* ]]; then
        echo "FAIL $(basename "$file"): group is not keyed on '$BRANCH_KEY':$group"
        failures=$((failures + 1))
    fi
done

if (( checked == 0 )); then
    echo "FAIL no workflow with push and pull_request triggers and a concurrency group was found in $WORKFLOWS"
    exit 1
fi
if (( failures > 0 )); then
    echo "$failures of $checked workflow(s) run twice for a branch with an open pull request"
    exit 1
fi
echo "ok: $checked workflow(s) share one concurrency group between a branch push and its pull request"
