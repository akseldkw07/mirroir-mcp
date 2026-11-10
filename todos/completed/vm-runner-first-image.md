> **Done 2026-11-09** (PR #22): the on-demand VM runner serves this fork's macOS jobs. Every
> item below ran on the MacBook; `build` passed end to end on the VM (50 min run, about 30 s
> to start against 26 min queued on GitHub), along with MCP compliance, `Build without
> embacle-ffi` (7 min against 22) and the install and installer jobs. Deviations: the image
> needed more than Accessibility and Screen Recording (see "Inside the image" in
> `docs/vm-runner.md`), and the runner boots a VM only while a job waits, at 6 cores and 12 GB.

# Bring the self-hosted VM runner up on the MacBook

Started 2026-11-09 in the PR that added `scripts/ci/vm-runner/` and the `MACOS_VM_RUNNER`
routing (see `docs/vm-runner.md`).

## To do

- [x] Install Tart 2.41.1 from its signed GitHub release (the Homebrew tap formula fails on
      current Homebrew) and put `tart` on `PATH`.
- [x] `scripts/ci/vm-runner/build-image.sh`: confirm `tart exec` reaches the
      `macos-sequoia-xcode` guest, and the runner and guest agent install.
- [x] Grant Accessibility and Screen Recording in the image for the FakeMirroring
      integration lanes; record which binary needs them in `docs/vm-runner.md`.
      (`Runner.Listener` is the responsible process; Input Monitoring, AppleEvents and the
      screen capture approval were needed too.)
- [x] `install-host-agent.sh`, then `gh variable set MACOS_VM_RUNNER --body mirroir-vm`, and
      run `build.yml` on a branch: every step green on the VM, host desktop untouched.
- [x] Check `installers.yml` and `install.yml` on the VM.
- [x] Compare wall-clock time with the hosted runner (baseline: `build` waited 26 min, ran 51).
- [x] Turn on "Require approval for all outside collaborators" under Settings → Actions.
