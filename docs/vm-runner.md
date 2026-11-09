# Self-hosted CI runner in a macOS VM

GitHub's hosted macOS runners are slow to get: on this fork a `build` job waited 12 to 39
minutes for a runner, then ran for 51. The same unit suites take about 3 minutes on an
Apple Silicon Mac. This runner lends a Mac to CI without giving CI the Mac's desktop:
every job runs in a fresh macOS VM ([Tart](https://tart.run)) that has its own window
server, so the integration tests that drive FakeMirroring with real clicks and keys never
touch the host's screen, mouse or keyboard.

## How it works

| Piece | Where it runs | What it does |
|---|---|---|
| `scripts/ci/vm-runner/host-loop.sh` | the Mac, under launchd | Clones a fresh VM from the `mirroir-ci` image, registers a one-job (JIT) runner with GitHub, shares its config with the VM, and deletes the VM and the runner once the VM shuts down |
| `scripts/ci/vm-runner/guest-agent.sh` | inside the VM, at login | Waits for the JIT config, runs exactly one job in the VM's desktop session, then shuts the VM down |
| `scripts/ci/vm-runner/build-image.sh` | the Mac, once | Pulls the Xcode base image and installs the pinned runner and the guest agent into `mirroir-ci` (through `install-guest.sh`) |
| `scripts/ci/vm-runner/install-host-agent.sh` | the Mac, once | Installs one launchd agent per slot that keeps `host-loop.sh` running |

Every job starts from the same clean image and its VM is deleted afterwards, so nothing a
job installs or leaves behind reaches the next job or the host.

## Routing jobs to it

The macOS jobs that a push or pull request starts use this `runs-on`:

```yaml
runs-on: ${{ (github.event_name != 'pull_request' || !github.event.pull_request.head.repo.fork) && vars.MACOS_VM_RUNNER || 'macos-15' }}
```

- With the repository variable `MACOS_VM_RUNNER` unset, every job stays on GitHub's
  `macos-15` runner. Upstream never sets it, so its CI is unchanged.
- Set it to the runner label (`mirroir-vm`) to send the jobs to the VM runner.
- A pull request from another fork always runs on GitHub's runner: its code never reaches
  this Mac.

`scripts/ci/vm-runner-routing-test.sh` keeps every such job on that expression. The
release workflow and the `macos-26` and `macos-latest` jobs stay on GitHub's runners.

## Setup

1. Install Tart from its [signed release](https://github.com/cirruslabs/tart/releases)
   (the `cirruslabs/cli` Homebrew tap fails on current Homebrew), and put `tart` on `PATH`.
2. Build the image. The first pull downloads tens of GB; the image holds about 60 GB.

   ```bash
   scripts/ci/vm-runner/build-image.sh
   ```

3. Start the runner loop. One slot by default; Apple's license allows two macOS VMs at once
   (`VM_RUNNER_SLOTS=2`).

   ```bash
   VM_RUNNER_REPO=akseldkw07/mirroir-mcp scripts/ci/vm-runner/install-host-agent.sh
   ```

4. Route the jobs to it:

   ```bash
   gh variable set MACOS_VM_RUNNER --body mirroir-vm
   ```

5. Require approval before workflows run for outside contributors (Settings → Actions →
   General). The routing already keeps fork pull requests off this runner; this keeps a
   first-time contributor's workflow edits from running anywhere without review.

## Switching it off

```bash
gh variable delete MACOS_VM_RUNNER              # jobs go back to GitHub's runners
scripts/ci/vm-runner/install-host-agent.sh --uninstall
```

Jobs routed to the VM runner wait for it, so delete the variable before the Mac goes away
for long (travel, a closed lid): otherwise they queue until GitHub gives up after 24 hours.

## Still to verify on the first image

- **`tart exec`.** `build-image.sh` reaches the VM through `tart exec`, which needs the Tart
  guest agent in the base image.
- **Permissions for the integration tests.** GitHub's runner image grants Accessibility and
  Screen Recording ahead of time; the FakeMirroring lanes in `build.yml` need both. Grant
  them in the image once, then rebuild clones from it.
- **The installer jobs** (`installers.yml`, `install.yml`) on a VM where the setup actions
  install every tool themselves.

## Testing

```bash
bash scripts/ci/vm-runner/test.sh               # host-loop.sh against stub tart and gh
bash scripts/ci/vm-runner-routing-test.sh       # every macOS push/PR job is routable
bash scripts/ci/concurrency-groups-test.sh      # a branch push and its PR share one group
```

The `Workflow checks` workflow runs all three on GitHub.
