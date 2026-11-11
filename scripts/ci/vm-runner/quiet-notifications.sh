#!/bin/bash
# ABOUTME: Runs inside the image VM (install-guest.sh calls it): turns Notification Center's banners off
# ABOUTME: for good, so no banner can sit over the FakeMirroring window during a job.

set -euo pipefail

# Notification Center draws every banner in one window the size of the display.
# On a desktop the user dismisses a banner; in a job VM no one does, so a banner
# that waits for a click (macOS 15's "See what's new", measured 2026-11-10) stays
# up, and input refuses every click while it shows. Disabling the agent keeps it
# off across reboots, and the job VMs cloned from the image inherit that.
AGENT="gui/$(id -u)/com.apple.notificationcenterui.agent"

launchctl disable "$AGENT"
# Not loaded (already stopped) is fine: disabled, it does not come back.
launchctl bootout "$AGENT" 2>/dev/null || true
echo "Notification Center's banners are off ($AGENT disabled)"
