# CI jobs die when the Mac sleeps under the VM runner

Seen on PR #26 (2026-11-11), PR #28 (2026-11-14, all four macOS workflows) and again on
PR #28's Source install job (2026-11-15): "The self-hosted runner lost communication with
the server", with no failed test step. On 2026-11-14 the power log shows the Mac going to
sleep again and again while jobs ran, and it was on battery.

`scripts/ci/vm-runner/host-loop.sh` holds no sleep assertion, so nothing keeps the Mac awake
while a job VM runs.

## To do

1. Failing test first in `scripts/ci/vm-runner/test.sh` (stub `caffeinate`): a job VM runs
   under a sleep assertion, and the idle loop holds none.
2. Wrap `tart run` in `caffeinate -i` (and `-s` on AC power) for the life of the VM only, so
   an idle runner still lets the Mac sleep.
3. Note in `docs/vm-runner.md` that a job on battery can still be cut short by low power.
