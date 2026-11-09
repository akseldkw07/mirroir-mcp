#!/usr/bin/env bash
# ABOUTME: Tests host-loop.sh against stub tart and gh commands on PATH, which record every call.
# ABOUTME: Nothing reaches a real VM or GitHub.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

cat > "$WORK/bin/tart" <<'EOF'
#!/usr/bin/env bash
echo "tart $*" >> "$STUB_LOG"
# `run` keeps the jitconfig the guest would read from the shared job directory.
if [[ "$1" == "run" ]]; then
    for arg in "$@"; do
        [[ "$arg" == --dir=job:* ]] && cp "${arg#--dir=job:}/jitconfig" "$STUB_SEEN_JIT"
    done
    exit "${STUB_RUN_EXIT:-0}"
fi
[[ "$1" == "clone" ]] && exit "${STUB_CLONE_EXIT:-0}"
exit 0
EOF

cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_LOG"
[[ "$*" == *generate-jitconfig* ]] && echo '{"runner":{"id":4321},"encoded_jit_config":"JIT-TOKEN"}'
# Runs with a job waiting for the label: run 777 holds STUB_WAITING_JOBS of them.
[[ "$*" == *"actions/runs?status="* ]] && echo 777
[[ "$*" == *"actions/runs/777/jobs"* ]] && echo "${STUB_WAITING_JOBS:-1}"
# GitHub removes a one-job runner after its job, so deleting it again is a 404.
[[ "$*" == *"-X DELETE"* ]] && exit 1
exit 0
EOF
chmod 755 "$WORK/bin/tart" "$WORK/bin/gh"

export PATH="$WORK/bin:$PATH"
export VM_RUNNER_REPO=owner/repo VM_RUNNER_IMAGE=base-image VM_RUNNER_LABEL=test-label
export STUB_LOG="$WORK/calls.log" STUB_SEEN_JIT="$WORK/seen-jit"
export VM_RUNNER_IDLE_POLL_SECS=1

# With no job waiting, the loop keeps polling GitHub and starts no VM.
: > "$STUB_LOG"
STUB_WAITING_JOBS=0 bash "$HERE/host-loop.sh" --once > "$WORK/out.log" 2>&1 &
idle_pid=$!
sleep 3
kill "$idle_pid" 2>/dev/null || true
wait "$idle_pid" 2>/dev/null || true
if ! grep -q '^tart clone' "$STUB_LOG" && grep -q 'actions/runs?status=' "$STUB_LOG"; then
    echo "ok   no VM boots while no job is waiting"
else
    echo "FAIL no VM boots while no job is waiting"; cat "$STUB_LOG" "$WORK/out.log"; exit 1
fi

: > "$STUB_LOG"
if bash "$HERE/host-loop.sh" --once > "$WORK/out.log" 2>&1; then status=0; else status=$?; fi
if (( status == 0 )); then
    echo "ok   a clean job exits 0, though its runner is already gone"
else
    echo "FAIL a clean job exits 0, though its runner is already gone (exit $status)"
    cat "$STUB_LOG" "$WORK/out.log"; exit 1
fi
if grep -q '^tart clone base-image mirroir-vm-' "$STUB_LOG"; then
    echo "ok   the VM is cloned from the image"
else
    echo "FAIL the VM is cloned from the image"; cat "$STUB_LOG" "$WORK/out.log"; exit 1
fi
if [[ "$(cat "$STUB_SEEN_JIT" 2>/dev/null)" == JIT-TOKEN ]]; then
    echo "ok   the VM gets its JIT config through the shared job directory"
else
    echo "FAIL the VM gets its JIT config through the shared job directory"; cat "$STUB_LOG"; exit 1
fi
if grep -q '^tart delete mirroir-vm-' "$STUB_LOG" \
    && grep -q 'gh api -X DELETE repos/owner/repo/actions/runners/4321' "$STUB_LOG"; then
    echo "ok   the VM and its runner registration are deleted after the job"
else
    echo "FAIL the VM and its runner registration are deleted after the job"; cat "$STUB_LOG"; exit 1
fi

: > "$STUB_LOG"
if STUB_RUN_EXIT=3 bash "$HERE/host-loop.sh" --once > "$WORK/out.log" 2>&1; then status=0; else status=$?; fi
if (( status != 0 )) && grep -q '^tart delete mirroir-vm-' "$STUB_LOG" \
    && grep -q 'actions/runners/4321' "$STUB_LOG"; then
    echo "ok   a failed VM fails --once and is still deleted with its runner"
else
    echo "FAIL a failed VM fails --once and is still deleted with its runner (exit $status)"
    cat "$STUB_LOG" "$WORK/out.log"; exit 1
fi

: > "$STUB_LOG"
if STUB_CLONE_EXIT=1 bash "$HERE/host-loop.sh" --once > "$WORK/out.log" 2>&1; then status=0; else status=$?; fi
if (( status != 0 )) && ! grep -q generate-jitconfig "$STUB_LOG"; then
    echo "ok   a failed clone fails --once and registers no runner"
else
    echo "FAIL a failed clone fails --once and registers no runner (exit $status)"
    cat "$STUB_LOG" "$WORK/out.log"; exit 1
fi
