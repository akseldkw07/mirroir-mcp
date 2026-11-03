"""Deploy this checkout to Claude Desktop. Run from the post-merge hook on main
(.pre-commit-config.yaml, via mcp-utils), or by hand: `python3 scripts/deploy.py`.

Claude Desktop runs this checkout's release binary through mcp-compat, which stays connected
to Desktop and starts the server again when it's stopped. So deploying builds the release
binary and stops running server processes; the next tool call starts the new build, with no
Desktop restart.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / ".build" / "release" / "mirroir-mcp"
CONFIG = (
    Path.home()
    / "Library"
    / "Application Support"
    / "Claude"
    / "claude_desktop_config.json"
)
COMPAT = Path.home() / "coding" / "mcp" / "mcp-utils" / "dist" / "compat" / "cli.js"
NAME = "iphone-mirror"


def main() -> None:
    # Without embacle-ffi installed the build falls back to Apple Vision OCR either way;
    # the variable keeps it that way if the library shows up later.
    env = {**os.environ, "MIRROIR_DISABLE_EMBACLE": "1"}
    subprocess.run(
        ["swift", "build", "-c", "release", "--product", "mirroir-mcp"],
        cwd=ROOT,
        env=env,
        check=True,
    )

    config = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    entries = [
        name
        for name, entry in config.get("mcpServers", {}).items()
        if str(SERVER) in entry.get("args", [])
    ]
    if not entries:
        print(
            f'{CONFIG} has no server running this checkout. Add this under "mcpServers", then '
            "restart Claude Desktop:\n"
            + json.dumps(
                {
                    NAME: {
                        "command": shutil.which("node")
                        or "node",  # Desktop has no PATH
                        "args": [str(COMPAT), "--name", NAME, "--", str(SERVER)],
                    }
                },
                indent=2,
            ),
            file=sys.stderr,
        )

    # only the server (argv[0] is SERVER), never mcp-compat itself
    ps = subprocess.run(
        ["ps", "-axo", "pid=,args="], capture_output=True, text=True, check=True
    )
    stopped = 0
    for line in ps.stdout.splitlines():
        pid, _, args = line.strip().partition(" ")
        if args.strip().split(" ")[0] == str(SERVER):
            os.kill(int(pid), signal.SIGTERM)
            stopped += 1
    print(
        f"deployed {SERVER} ({', '.join(entries) or 'not in the Desktop config'}); stopped {stopped} running server(s)"
    )


if __name__ == "__main__":
    main()
