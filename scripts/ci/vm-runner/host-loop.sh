#!/usr/bin/env bash
# ABOUTME: Host side of the self-hosted CI runner: clones a fresh macOS VM per job, registers a one-job
# ABOUTME: (JIT) GitHub runner in it, waits for the VM to finish the job, then deletes the VM and the runner.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: host-loop.sh [--once] [--slot N]

Keeps one ephemeral VM runner waiting for a job, forever (or once with --once).
Run one loop per slot; Apple's license allows two macOS VMs per Mac.

Environment:
  VM_RUNNER_REPO      owner/repo the runner serves (required)
  VM_RUNNER_IMAGE     local Tart VM to clone per job (default: mirroir-ci)
  VM_RUNNER_LABEL     runner label the workflows target through MACOS_VM_RUNNER (default: mirroir-vm)
  VM_RUNNER_MAX_SECS  stop a VM that has run this long (default: 10800, three hours)
  VM_RUNNER_GROUP_ID  runner group id (default: 1, the repository's default group)
EOF
}

once=0
slot=1
while (( $# > 0 )); do
    case "$1" in
        --once) once=1 ;;
        --slot) slot="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

: "${VM_RUNNER_REPO:?set VM_RUNNER_REPO to owner/repo}"
IMAGE="${VM_RUNNER_IMAGE:-mirroir-ci}"
LABEL="${VM_RUNNER_LABEL:-mirroir-vm}"
MAX_SECS="${VM_RUNNER_MAX_SECS:-10800}"
GROUP_ID="${VM_RUNNER_GROUP_ID:-1}"
POLL_SECS=5

log() { echo "[vm-runner $slot $(date +%H:%M:%S)] $*"; }

# One job: a fresh VM, a runner registered for exactly one job, and cleanup
# of both whatever happens to the job. A subshell, so its EXIT trap cleans up
# on every path; each step checks its own failure, since `run_one || ...`
# turns errexit off inside it.
run_one() (
    name="mirroir-vm-$(hostname -s)-$slot-$(date +%s)"
    job_dir="$(mktemp -d)" || exit 1
    runner_id=""
    vm_pid=""

    cleanup() {
        [[ -n "$vm_pid" ]] && kill "$vm_pid" 2>/dev/null
        tart stop "$name" >/dev/null 2>&1
        tart delete "$name" >/dev/null 2>&1
        # An ephemeral runner unregisters itself after its job; one whose VM
        # was stopped first would linger as an offline runner.
        if [[ -n "$runner_id" ]]; then
            gh api -X DELETE "repos/$VM_RUNNER_REPO/actions/runners/$runner_id" >/dev/null 2>&1
        fi
        rm -rf "$job_dir"
    }
    trap cleanup EXIT

    log "cloning $IMAGE into $name"
    tart clone "$IMAGE" "$name" || exit 1

    reply="$(gh api -X POST "repos/$VM_RUNNER_REPO/actions/runners/generate-jitconfig" \
        -f name="$name" -F runner_group_id="$GROUP_ID" -f "labels[]=$LABEL" -f work_folder=_work)" || exit 1
    runner_id="$(jq -r '.runner.id' <<<"$reply")" || exit 1
    # The guest agent reads this file from the shared directory and starts the runner with it.
    (umask 077 && jq -r '.encoded_jit_config' <<<"$reply" > "$job_dir/jitconfig") || exit 1

    log "starting $name (runner $runner_id, label $LABEL)"
    tart run --no-graphics --dir="job:$job_dir" "$name" &
    vm_pid=$!
    started=$SECONDS
    while kill -0 "$vm_pid" 2>/dev/null; do
        if (( SECONDS - started >= MAX_SECS )); then
            log "$name ran past ${MAX_SECS}s; stopping it"
            exit 1
        fi
        sleep "$POLL_SECS"
    done
    wait "$vm_pid"
    status=$?
    vm_pid=""
    log "$name finished after $((SECONDS - started))s (tart run exit $status)"
    exit "$status"
)

FAILURE_BACKOFF_SECS=30

while true; do
    if run_one; then
        (( once )) && break
    else
        log "job VM failed: exit $?"
        (( once )) && exit 1
        # A missing image or an expired gh login fails every time; don't spin on it.
        sleep "$FAILURE_BACKOFF_SECS"
    fi
done
