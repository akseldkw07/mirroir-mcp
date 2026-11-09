#!/usr/bin/env bash
# ABOUTME: Host side of the self-hosted CI runner: clones a fresh macOS VM per job, registers a one-job
# ABOUTME: (JIT) GitHub runner in it, waits for the VM to finish the job, then deletes the VM and the runner.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: host-loop.sh [--once] [--slot N]

Waits until GitHub has a job queued for the runner's label, then serves it in a
fresh VM, forever (or once with --once). No VM runs while nothing is queued.
Run one loop per slot; Apple's license allows two macOS VMs per Mac.

Environment:
  VM_RUNNER_REPO      owner/repo the runner serves (required)
  VM_RUNNER_IMAGE     local Tart VM to clone per job (default: mirroir-ci)
  VM_RUNNER_LABEL     runner label the workflows target through MACOS_VM_RUNNER (default: mirroir-vm)
  VM_RUNNER_MAX_SECS  stop a VM that has run this long (default: 10800, three hours)
  VM_RUNNER_GROUP_ID  runner group id (default: 1, the repository's default group)
  VM_RUNNER_IDLE_POLL_SECS  how often to ask GitHub for a queued job (default: 20)
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
IDLE_POLL_SECS="${VM_RUNNER_IDLE_POLL_SECS:-20}"
# A VM boots for a queued job, but the job can be cancelled (a push run's
# duplicate, once its pull request run starts) or taken by another runner
# before this one is up. A runner that has run no job by then is stopped.
IDLE_GRACE_SECS="${VM_RUNNER_IDLE_GRACE_SECS:-300}"

log() { echo "[vm-runner $slot $(date +%H:%M:%S)] $*"; }

# Whether GitHub has a job queued for LABEL. A job of an in-progress run can
# still be queued (it waits for a runner while its siblings run), so both kinds
# of run are checked.
job_waiting() {
    local status run waiting
    for status in queued in_progress; do
        for run in $(gh api "repos/$VM_RUNNER_REPO/actions/runs?status=$status&per_page=50" \
                --jq '.workflow_runs[].id' 2>/dev/null); do
            waiting="$(gh api "repos/$VM_RUNNER_REPO/actions/runs/$run/jobs?per_page=100" \
                --jq "[.jobs[] | select(.status == \"queued\" and (.labels | index(\"$LABEL\")))] | length" \
                2>/dev/null)"
            (( ${waiting:-0} > 0 )) && return 0
        done
    done
    return 1
}

# One job: a fresh VM, a runner registered for exactly one job, and cleanup
# of both whatever happens to the job. A subshell, so its EXIT trap cleans up
# on every path; each step checks its own failure, since `run_one || ...`
# turns errexit off inside it.
run_one() (
    name="mirroir-vm-$(hostname -s)-$slot-$(date +%s)"
    job_dir="$(mktemp -d)" || exit 1
    runner_id=""
    vm_pid=""

    # Best effort, every step: errexit still applies inside an EXIT trap, so
    # one failing command here would replace the job's exit status.
    cleanup() {
        if [[ -n "$vm_pid" ]]; then kill "$vm_pid" 2>/dev/null || true; fi
        tart stop "$name" >/dev/null 2>&1 || true
        tart delete "$name" >/dev/null 2>&1 || true
        # An ephemeral runner unregisters itself after its job (so this is
        # usually a 404); one whose VM was stopped first would linger offline.
        if [[ -n "$runner_id" ]]; then
            gh api -X DELETE "repos/$VM_RUNNER_REPO/actions/runners/$runner_id" >/dev/null 2>&1 || true
        fi
        rm -rf "$job_dir" || true
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
    ran_a_job=0
    while kill -0 "$vm_pid" 2>/dev/null; do
        if (( SECONDS - started >= MAX_SECS )); then
            log "$name ran past ${MAX_SECS}s; stopping it"
            exit 1
        fi
        if (( ! ran_a_job )); then
            busy="$(gh api "repos/$VM_RUNNER_REPO/actions/runners/$runner_id" --jq .busy 2>/dev/null)"
            if [[ "$busy" == true ]]; then
                ran_a_job=1
            elif (( SECONDS - started >= IDLE_GRACE_SECS )); then
                log "$name got no job within ${IDLE_GRACE_SECS}s; stopping it"
                exit 0
            fi
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
    # On demand: no VM, and none of its cores or memory, until a job waits for one.
    until job_waiting; do sleep "$IDLE_POLL_SECS"; done
    if run_one; then
        (( once )) && break
    else
        log "job VM failed: exit $?"
        (( once )) && exit 1
        # A missing image or an expired gh login fails every time; don't spin on it.
        sleep "$FAILURE_BACKOFF_SECS"
    fi
done
