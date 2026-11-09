#!/usr/bin/env bash
# ABOUTME: Builds the local Tart VM image the CI runner clones per job: pulls the Xcode base image,
# ABOUTME: sizes it, and installs the GitHub Actions runner and its login agent inside it.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# GitHub's macos-15 runner ships Xcode 16 on Sequoia; this image matches it.
BASE="${VM_RUNNER_BASE:-ghcr.io/cirruslabs/macos-sequoia-xcode:latest}"
IMAGE="${VM_RUNNER_IMAGE:-mirroir-ci}"
CPUS="${VM_RUNNER_CPUS:-6}"
MEMORY_MB="${VM_RUNNER_MEMORY_MB:-16384}"
BOOT_WAIT_SECS=300

log() { echo "[build-image $(date +%H:%M:%S)] $*"; }

if tart list --quiet | grep -qx "$IMAGE"; then
    echo "A VM named '$IMAGE' exists already. Delete it first: tart delete $IMAGE" >&2
    exit 1
fi

log "cloning $BASE into $IMAGE (the first pull downloads tens of GB)"
tart clone "$BASE" "$IMAGE"
tart set "$IMAGE" --cpu "$CPUS" --memory "$MEMORY_MB"

log "booting $IMAGE"
tart run --no-graphics --dir="setup:$HERE" "$IMAGE" &
vm_pid=$!
trap 'tart stop "$IMAGE" >/dev/null 2>&1 || true' EXIT

waited=0
until tart exec "$IMAGE" true >/dev/null 2>&1; do
    if (( waited >= BOOT_WAIT_SECS )); then
        echo "$IMAGE did not answer tart exec within ${BOOT_WAIT_SECS}s" >&2
        exit 1
    fi
    sleep 5
    waited=$((waited + 5))
done

log "installing the runner"
tart exec "$IMAGE" bash "/Volumes/My Shared Files/setup/install-guest.sh"

log "shutting $IMAGE down"
tart exec "$IMAGE" sudo shutdown -h now || true
wait "$vm_pid" || true
trap - EXIT
log "$IMAGE is ready: start host-loop.sh to serve jobs"
