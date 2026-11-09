#!/usr/bin/env bash
# ABOUTME: Checks that every macOS job a push or pull request starts can run on the self-hosted VM runner,
# ABOUTME: and that a pull request from another fork never reaches it.

set -euo pipefail

WORKFLOWS="${1:-$(cd "$(dirname "$0")/../../.github/workflows" && pwd)}"
# MACOS_VM_RUNNER (a repository variable) names the VM runner's label. Unset,
# the job keeps GitHub's macos-15 runner. A pull request from another repository
# always does: its code must not run on the maintainer's Mac. The check compares
# repositories, not `head.repo.fork`, which is true for every pull request in a
# repository that is itself a fork (measured 2026-11-09 on akseldkw07/mirroir-mcp).
ROUTED="runs-on: \${{ (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository) && vars.MACOS_VM_RUNNER || 'macos-15' }}"

failures=0
routed=0
for file in "$WORKFLOWS"/*.yml; do
    grep -qE '^  (push|pull_request):' "$file" || continue
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ "$trimmed" == "$ROUTED" ]]; then
            routed=$((routed + 1))
        elif [[ "$trimmed" == "runs-on: macos-15" || "$trimmed" == *MACOS_VM_RUNNER* ]]; then
            echo "FAIL $(basename "$file"): '$trimmed' is not the routed runner expression"
            failures=$((failures + 1))
        fi
    done < <(grep -E '^\s+runs-on:' "$file")
done

if (( routed == 0 )); then
    echo "FAIL no macOS job in $WORKFLOWS is routed to the VM runner"
    exit 1
fi
if (( failures > 0 )); then
    echo "$failures macOS job(s) bypass the VM runner routing"
    exit 1
fi
echo "ok: $routed macOS job(s) run on the VM runner when MACOS_VM_RUNNER is set"
