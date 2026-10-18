# Evidence index

Raw artefacts supporting [`../ROOTING-RESEARCH.md`](../ROOTING-RESEARCH.md).

| File | What it is |
|---|---|
| `root-evidence.json` | Machine-readable output of the successful root run (identity, `CapEff`, command results, integrity assertions). |
| `root-run-full.log` | Console log of that run. |
| `recon-as-sdk.txt` | Unprivileged reconnaissance on the TV as `uid=901(sdk)` / SMACK `System`: identity, kernel, Tizen build, `getcap` inventory, world-writable `/dev` nodes, mounts, `unshare` test. |
| `sdb-protocol-capture.txt` | Raw SDB wire capture (`CNXN`/`OPEN`/`OKAY`/`WRTE`/`CLSE`) between host and TV. |
| `injection.txt` | The exact `SVE-2025-50109` package-name injection argument, its decoded form, the timing oracle, and UEP notes. |
| `do_root.py` | The driver that runs the upstream archive-root route with the three TV-specific adaptations from §6 of the write-up. |

## Key facts asserted by this evidence

* Root agent authenticated as `uid=0 euid=0 gid=0 egid=0`, `CapEff=0000003fffffffff`.
* `/etc/shadow` (mode `0000`, root-owned) was read.
* A write test succeeded in the root-owned `/opt/usr` directory.
* `/etc/passwd` and `/usr/share/sdbd/public.pem` reflected the bind-mounted
  attacker copies (proving the private mount namespace and trust-anchor substitution).
* `system_files_unchanged: true` and `staging_cleaned: true` after the run.

The root run is fully reversible: reboot clears everything.
