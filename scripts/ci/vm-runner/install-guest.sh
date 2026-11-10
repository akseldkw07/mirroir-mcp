#!/bin/bash
# ABOUTME: Runs once inside the image VM (build-image.sh calls it through tart exec): installs the pinned
# ABOUTME: GitHub Actions runner and the login agent that runs one job per boot.

set -euo pipefail

RUNNER_VERSION="2.338.2"
RUNNER_SHA256="25a065af409ffa317ab4d5a3b614dd15fc9c40f2172bc1b35a1b1258e919a388"
RUNNER_TARBALL="actions-runner-osx-arm64-$RUNNER_VERSION.tar.gz"
SETUP_DIR="/Volumes/My Shared Files/setup"
AGENT_LABEL="com.mirroir.vm-runner.guest"

mkdir -p "$HOME/actions-runner" "$HOME/vm-runner" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

cd "$HOME/actions-runner"
curl -fsSL -o "$RUNNER_TARBALL" \
    "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/$RUNNER_TARBALL"
echo "$RUNNER_SHA256  $RUNNER_TARBALL" | shasum -a 256 -c -
tar -xzf "$RUNNER_TARBALL"
rm "$RUNNER_TARBALL"

install -m 755 "$SETUP_DIR/guest-agent.sh" "$HOME/vm-runner/guest-agent.sh"

cat > "$HOME/Library/LaunchAgents/$AGENT_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/vm-runner/guest-agent.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/vm-runner.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/vm-runner.log</string>
</dict>
</plist>
EOF

# The FakeMirroring lanes post clicks and keys, read input, capture the screen
# and script System Events, as GitHub's runner image allows ahead of time. A
# job's responsible process is the runner's Runner.Listener (measured
# 2026-11-09: every TCC request from a job named it). Without grants, macOS
# shows consent dialogs no one can answer and the job's input hangs. The base
# image grants these to its SSH entry point; its rows are copied from both TCC
# databases (AppleEvents lives in the user's), and Input Monitoring, which that
# entry point lacks, is added. Writing them needs SIP off, which the base image has.
RESPONSIBLE="$HOME/actions-runner/bin/Runner.Listener"
TEMPLATE_CLIENT="/usr/libexec/sshd-keygen-wrapper"
SYSTEM_TCC="/Library/Application Support/com.apple.TCC/TCC.db"
USER_TCC="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
COLUMNS_AFTER_CLIENT="auth_value, auth_reason, auth_version, NULL, policy_id,
    indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity,
    flags, last_modified, pid, pid_version, boot_uuid, last_reminded"
if ! csrutil status | grep -q disabled; then
    echo "SIP is enabled in this image, so the test permissions cannot be granted" >&2
    exit 1
fi
for db in "$SYSTEM_TCC" "$USER_TCC"; do
    rows="$(sudo sqlite3 "$db" "SELECT count(*) FROM access WHERE client='$TEMPLATE_CLIENT';")"
    if (( rows == 0 )); then
        echo "no TCC grants for $TEMPLATE_CLIENT to copy in $db" >&2
        exit 1
    fi
    sudo sqlite3 "$db" "INSERT OR REPLACE INTO access
        SELECT service, '$RESPONSIBLE', 1, $COLUMNS_AFTER_CLIENT
        FROM access WHERE client='$TEMPLATE_CLIENT';"
done
sudo sqlite3 "$SYSTEM_TCC" "INSERT OR REPLACE INTO access
    SELECT 'kTCCServiceListenEvent', '$RESPONSIBLE', 1, $COLUMNS_AFTER_CLIENT
    FROM access WHERE client='$TEMPLATE_CLIENT' AND service='kTCCServicePostEvent';"
# Sequoia also asks, outside TCC, before a process may capture the screen
# without the system window picker ("... is requesting to bypass the system
# private window picker"). That dialog takes keyboard focus, so a test's typing
# lands in it (measured 2026-11-09). Approvals carry an expiry date; these never lapse.
WORKSPACE="$HOME/actions-runner/_work/${VM_RUNNER_REPO_NAME:-mirroir-mcp}/${VM_RUNNER_REPO_NAME:-mirroir-mcp}"
CAPTURE_APPROVALS="$HOME/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals"
for capturer in /bin/bash "$RESPONSIBLE" \
    "$WORKSPACE/.build/arm64-apple-macosx/release/mirroir-mcp" \
    "$WORKSPACE/.build/arm64-apple-macosx/debug/mirroir-mcp" \
    "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest"; do
    defaults write "$CAPTURE_APPROVALS" "$capturer" -date "3024-01-01 00:00:00 +0000"
done
echo "screen capture pre-approved for: $(defaults read "$CAPTURE_APPROVALS" | grep -c '=') processes"

for db in "$SYSTEM_TCC" "$USER_TCC"; do
    scope="system"; [[ "$db" == "$USER_TCC" ]] && scope="user"
    echo "granted to Runner.Listener in the $scope TCC database:" \
        "$(sudo sqlite3 "$db" "SELECT group_concat(service || coalesce('→' || nullif(indirect_object_identifier, 'UNUSED'), ''), ' ') FROM access WHERE client='$RESPONSIBLE';")"
done

bash "$SETUP_DIR/quiet-notifications.sh"

echo "runner $RUNNER_VERSION and $AGENT_LABEL installed"
