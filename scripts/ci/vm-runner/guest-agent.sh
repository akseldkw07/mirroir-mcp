#!/bin/bash
# ABOUTME: Guest side of the self-hosted CI runner, started at login inside the VM's own desktop session.
# ABOUTME: Runs one GitHub job with the JIT config host-loop.sh shares, then shuts the VM down.

set -uo pipefail

# Tart mounts `--dir=job:<path>` here. Commands use absolute paths: `tart exec`
# and launchd start with a minimal PATH.
JIT_FILE="/Volumes/My Shared Files/job/jitconfig"
RUNNER_DIR="$HOME/actions-runner"
WAIT_SECS=300

log() { echo "[guest-agent $(date +%H:%M:%S)] $*"; }

waited=0
until [[ -s "$JIT_FILE" ]]; do
    if (( waited >= WAIT_SECS )); then
        log "no JIT config at $JIT_FILE after ${WAIT_SECS}s"
        sudo /sbin/shutdown -h now
        exit 1
    fi
    sleep 2
    waited=$((waited + 2))
done

# launchd starts this agent with /usr/bin:/bin:/usr/sbin:/sbin only. Jobs expect
# a login shell's PATH, Homebrew's tools first, as on GitHub's macOS runners.
eval "$(/usr/libexec/path_helper -s)"
eval "$(/opt/homebrew/bin/brew shellenv)"

# The runner starts in the login session, so jobs get the VM's window server:
# FakeMirroring's integration tests need a real desktop, which an SSH session lacks.
log "starting the runner for one job"
cd "$RUNNER_DIR" || exit 1
./run.sh --jitconfig "$(cat "$JIT_FILE")"
log "runner exited with $?; shutting down"
sudo /sbin/shutdown -h now
