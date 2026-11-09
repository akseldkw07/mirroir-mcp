#!/usr/bin/env bash
# ABOUTME: Builds the local Tart VM image the CI runner clones per job: pulls the Xcode base image,
# ABOUTME: sizes it, and installs the GitHub Actions runner and its login agent inside it.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# GitHub's macos-15 runner ships Xcode 16 on Sequoia; this image matches it.
BASE="${VM_RUNNER_BASE:-ghcr.io/cirruslabs/macos-sequoia-xcode:latest}"
IMAGE="${VM_RUNNER_IMAGE:-mirroir-ci}"
CPUS="${VM_RUNNER_CPUS:-6}"
MEMORY_MB="${VM_RUNNER_MEMORY_MB:-12288}"
# GitHub's macOS runners have a 1920x1080 display. Tart's default, 1024x768, is
# shorter than FakeMirroring's 898-point window: taps on its tab bar landed off
# the screen (measured 2026-11-09).
DISPLAY_SIZE="1920x1080"
BOOT_WAIT_SECS=300
AGENT_LABEL="com.mirroir.vm-runner.guest"

log() { echo "[build-image $(date +%H:%M:%S)] $*"; }

if tart list --quiet | grep -qx "$IMAGE"; then
    echo "A VM named '$IMAGE' exists already. Delete it first: tart delete $IMAGE" >&2
    exit 1
fi

log "cloning $BASE into $IMAGE (the first pull downloads tens of GB)"
tart clone "$BASE" "$IMAGE"
tart set "$IMAGE" --cpu "$CPUS" --memory "$MEMORY_MB" --display "$DISPLAY_SIZE"

# Boot the image headless and wait until tart exec reaches it.
boot() {
    log "booting $IMAGE"
    tart run --no-graphics --dir="setup:$HERE" "$IMAGE" &
    vm_pid=$!
    local waited=0
    until tart exec "$IMAGE" true >/dev/null 2>&1; do
        if (( waited >= BOOT_WAIT_SECS )); then
            echo "$IMAGE did not answer tart exec within ${BOOT_WAIT_SECS}s" >&2
            exit 1
        fi
        sleep 5
        waited=$((waited + 5))
    done
}

shut_down() {
    log "shutting $IMAGE down"
    tart exec "$IMAGE" sudo /sbin/shutdown -h now || true
    wait "$vm_pid" || true
}

trap 'tart stop "$IMAGE" >/dev/null 2>&1 || true' EXIT

boot
log "installing the runner"
tart exec "$IMAGE" bash "/Volumes/My Shared Files/setup/install-guest.sh"
shut_down

# macOS announces a new login agent with a "Background Items Added" banner at
# the next login. In a job VM that banner sits over the mirroring window and
# input refuses to click through it, so the image logs in once here: macOS
# records the agent, and the clones inherit the record and stay silent.
boot
waited=0
until tart exec "$IMAGE" bash -c "sudo sfltool dumpbtm 2>/dev/null | grep -q '$AGENT_LABEL'"; do
    if (( waited >= BOOT_WAIT_SECS )); then
        echo "macOS never recorded the $AGENT_LABEL login agent" >&2
        exit 1
    fi
    sleep 5
    waited=$((waited + 5))
done
log "macOS recorded the login agent"
shut_down

trap - EXIT
log "$IMAGE is ready: start host-loop.sh to serve jobs"
