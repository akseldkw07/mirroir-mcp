# Bring the self-hosted VM runner up on the MacBook

Started 2026-11-09 in the PR that added `scripts/ci/vm-runner/` and the `MACOS_VM_RUNNER`
routing (see `docs/vm-runner.md`). The code is in; nothing has run on a real VM yet.

## To do

- [ ] Install Tart 2.41.1 from its signed GitHub release (the Homebrew tap formula fails on
      current Homebrew) and put `tart` on `PATH`.
- [ ] `scripts/ci/vm-runner/build-image.sh`: confirm `tart exec` reaches the
      `macos-sequoia-xcode` guest, and the runner and guest agent install.
- [ ] Grant Accessibility and Screen Recording in the image for the FakeMirroring
      integration lanes; record which binary needs them in `docs/vm-runner.md`.
- [ ] `install-host-agent.sh`, then `gh variable set MACOS_VM_RUNNER --body mirroir-vm`, and
      run `build.yml` on a branch: every step green on the VM, host desktop untouched.
- [ ] Check `installers.yml` and `install.yml` on the VM.
- [ ] Compare wall-clock time with the hosted runner (baseline: `build` waited 26 min, ran 51).
- [ ] Turn on "Require approval for all outside collaborators" under Settings → Actions.
