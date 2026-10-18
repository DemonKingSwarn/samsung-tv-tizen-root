# Samsung QA55QEF1AULXL — debloat & annoyance removal

**Device:** QA55QEF1AULXL · Tizen `9.0` (product 4.0) · region IN · serial `<redacted>`
**Network:** `10.27.27.3` (RCR "Iris") · sdb port `26101` · dev mode was already on
**Firmware:** `T-RSLFUABC-0090-REL-202608061940`

> Paths below are relative to the repository root. The paper is in `paper/`, the
> long-form write-up is `ROOTING-RESEARCH.md`.

---

## 1. What was actually possible

Retail Samsung TVs do **not** give you a shell, even with Developer Mode on. The TV
reports:

```
intershell_support:disabled      <- no interactive shell, no `df`/`du`/`pkginfo`
sdbd_rootperm:disabled           <- no root
rootonoff_support:disabled
filesync_support:pushpull
platform_version:9.0
```

Only three commands work over sdb:

```sh
sdb -s <TV_IP>:26101 shell 0 applist          # list installed packages
sdb -s <TV_IP>:26101 shell 0 getduid          # device unique id
sdb -s <TV_IP>:26101 uninstall <PKGID>        # remove a package
```

Everything else (`sdb shell`, `dlog`, `sdb pull`) returns `closed`. There is **no way
to measure disk usage** from the PC — use `Settings → Support → Device Care → Manage
Storage` if you want a number.

The TV shipped with **514 apps**: 152 `org.tizen.*` + 302 `com.samsung.*` are platform
code that must not be touched lightly. Only 17 were store apps.

Two debloat passes are documented here:

1. **SDB-only** (§2–§3) — 514 → 511. This is everything the *supported* tooling allows.
2. **With root** (§3b) — 511 → **427**. Root bypasses the preload locks; see §9–§10 for
   how root is obtained and kept.

## 2. What was removed ✅

| App | Package ID | Verified gone |
|---|---|---|
| Samsung TV Plus (the auto-starting "Now Playing") | `HEPsqFNie0` | ✅ |
| `2025.SmartTV.Rose` (promo / ad pop-up) | `2025ePop01` | ✅ |
| `cmsWebApp` (unidentified web app) | `WykOS4t4F0` | ✅ |

Each removal was verified with a fresh `applist` diff. Package count went
**514 → 511**. Smart Hub, store, browser and launcher were re-checked and are intact.

## 3. What could NOT be removed 🔒

Tizen 9 locks most preloads. Two distinct failure modes were observed:

**a) Locked preloads** — `sdb uninstall` returns `can not uninstall app`:

- Spotify (`rJeHak5zRg`) + its recommendation/continue-watching services
- User Guide / e-Manual (`25emanual3`, `25emanual5`)
- ZEE5 (`wKDM33Rods`) + its service

**b) Blocked by a platform dependency** — refuses with
`Dependency [com.samsung.tv.googlecast-app] -> [ByJlgt0XeD] is not met`:

- Google Cast Settings (`ByJlgt0XeD`) — the Google Cast platform service needs it,
  so the TV will not let it go

Also still present (never selected): YouTube, JioHotstar, SonyLIV, India Today,
Privacy Choices.

**Kept on purpose (never remove):** YouTube, Privacy Choices, all `org.tizen.*` /
`com.samsung.*`, and `org.tizen.netflixlowmem`.

**Bottom line:** on this firmware only *3* packages were removable (all uninstallable
`wgt` store apps). Everything else is either platform code or a locked preload. This
is a firmware restriction, not a tooling limitation — no sdb command can override it.

## 3b. Removed with root — 511 → 427 (84 apps)

With a root shell (§9) the locks in §3 disappear: `pkgcmd -u -n <pkgid>` as root
uninstalls preloads that `sdb uninstall` refused, and cascading dependants go with
them. Removed on 2026-10-18, by group:

| Group | Direct | Total with dependants | What it removes |
|---|---|---|---|
| Ads / ACR / telemetry | 21 | 26 | `adplayer`, `ad-web-framework`, `targeted-ad-service`, `adplatform`, `acr-service-app`, `iacr`, `canalysis-service`, `*-analysis-dbmgr`, `*-recognition-dbmgr`, `photo/subtitle/xrfw-datamgr`, `samsung-analytics`, `pisa-service`, `context-aware-*`, `ai-discovery-sceneanalyzer`, `vd-sc-client-service` |
| Promo / auto-run | 3 | 3 | `tvPlusDeeplinker`, `reminder`, `ambientfte` (+ deleted the `tvplus_autorun_enable` / `bstr_tvplus_mode` flag files) |
| Gaming | 5 | 5 | `gamehome`, `gaminghub`, `ghdaemon`, `ghservice`, `gamepadguide` |
| Bixby / Alexa / voice AI | 19 | 24 | `bixby-*`, `mybixby`, `alexa-*`, `wakeup-engine-*`, `ondevice-voice`, `farfieldvoice`, `voiceid-service`, `voice-instant-app`, `voiceassistant-music`, `utterance-recommender-*`, `multi-llm-framework`, `AICompanion*`, `wakeupless` |
| SmartThings / IoT | 12 | 22 | `smartthings-*`, `SmartThingsApp`, `smartthingsfind-*`, `iot-hub-control`, `iotwidget*`, `iot-service-notification-v2`, `tvsensor/tvcamera-iot-*` |
| Samsung Health | 3 | 4 | `health-mde-service`, `health-mde-service-view`, `health-mde-setting`, `health-mde-workout-tracker` |
| Art / Ambient extras | 2 | 2 | `ambient-sound`, `GenerativeWallpaper` |

Native services that are **not** tpk packages (`sp-kpi`, `data-service`,
`media-analytics-service`, `reminder-service`, `ambient-ua-agent`) were stopped and
disabled separately — see `tools/tv-debloat-apply.sh`.

Verification after the change: `applist` 511 → 427, running services 146 → 138,
**zero failed units**, `display-manager` / launcher / security services still up.

Two handy discoveries (both are Samsung's own mechanisms, not hacks):

* **`pkgcmd -D -n <pkgid>`** deactivates a package without uninstalling it — the
  supported way to disable a preload.
* Uninstalling a package makes the firmware drop a **kill-switch marker** at
  `/opt/usr/share/systemd/system/<name>`, which the service units test with
  `ConditionPathExists=!/opt/usr/share/systemd/system/<name>`. Writing that same file
  by hand (it is on the writable `/opt` partition) permanently disables a service.
  `tools/tv-debloat-apply.sh` uses this for the units whose name differs from the
  package name.

**Kept on purpose:** YouTube, Privacy Choices, the store, browser, all DRM, all
`org.tizen.*` core, `com.samsung.tv.coba.*` (home UI) and `com.samsung.tv.home.*`
(home tabs), the unused store apps (Spotify/ZEE5/SonyLIV/JioHotstar/India Today/User
Guides), Google Cast Settings, Netflix and Prime Video, and Kids/TV Plus live.

## 4. Stop the ads / tracking / TV Plus re-download (recommended next step)

Deleting TV Plus is not always permanent: the TV can silently re-download preloads
from Samsung's `osb-*.samsungqbe.com` endpoints. Block them at DNS and the ads/ACR
telemetry disappear too.

**Easiest — point the TV at a filtering DNS:**

1. `Settings → All Settings → General & Privacy → Network → Network Status → IP Settings → DNS Settings`
2. Set **DNS Settings → Enter manually**, **DNS Server** =
   - AdGuard (blocks ads/trackers broadly): `94.140.14.14` (backup `94.140.15.15`)
   - or NextDNS (best for the custom domain list below — copy the two IPs NextDNS
     shows for your own configuration)
3. Save, then power-cycle the TV.

**Most precise — NextDNS custom Denylist:** paste the domains from
`samsung-tv-blocklist.txt` (drop the leading `0.0.0.0`), or paste into Pi-hole /
AdGuard Home as a local list. This list targets:

- Samsung Ads (`samsungads.com`, `samsungadhub.com`, `samsungtvads.com`, …)
- ACR / "Viewing Information Services" telemetry (`samsungacr.com`, …)
- **TV Plus re-download** (`osb-v2.samsungqbe.com`, `osb-apps.samsungqbe.com`, …)
- Smart Hub promo tiles / telemetry

> Do NOT blanket-block `samsung.com` / `samsungapps.com` — that breaks the app store
> and firmware updates.

## 5. Do these on the TV with the remote (no PC needed)

Turn off the tracking that feeds targeted ads:

```
Settings → All Settings → General & Privacy → Terms & Privacy
    → Viewing Information Services     OFF   (this is ACR)
    → Interest-Based Advertising       OFF
```

Stop the TV booting into the ad-filled home screen:

```
Settings → All Settings → General & Privacy → Smart Features
    → Autorun Smart Hub                OFF
    → Autorun Last App                 OFF
```

## 6. When you're done: turn Developer Mode OFF

Leaving it on writes debug logs, can interfere with DRM playback in some apps, and
keeps a debug bridge listening on your LAN.

```
Home → Apps → type 1 2 3 4 5 → Developer mode: OFF → reboot
```

## 7. Rollback / caveats

- Removed store apps can be reinstalled from the Samsung store (TV Plus included).
  The promo app and `cmsWebApp` are not in the store and only return via a firmware
  update / factory reset.
- A **factory reset or "Reset Smart Hub"** brings all preloads back.
- A **firmware update** *may* restore preloads. Blocking the `osb-*.samsungqbe.com`
  domains is what prevents silent re-download.
- Nobody can tell you how much space was freed — the TV won't report it. Check
  `Settings → Support → Device Care → Manage Storage` yourself.

## 8. Artifacts in this repository

- `README.md` — the repository overview and paper
- `docs/DEBLOAT.md` — this guide
- `samsung-tv-blocklist.txt` — hosts-format blocklist
- `applist-before.txt` (514), `applist-after.txt` (511, SDB-only),
  `applist-after-root.txt` (**427**, after the root debloat)
- `classify-applist.py` — the classifier used (from the
  [ardazeytin/samsung-tizen-tv-debloat](https://github.com/ardazeytin/samsung-tizen-tv-debloat) project)
- `ROOTING-RESEARCH.md` — write-up of the volatile root path on this exact TV (see §9)
- `paper/` — the same work as a Typst research paper (`main.typ`, `refs.bib`; PDF built locally)
- `evidence/` — raw root evidence, unprivileged recon, SDB wire capture, injection string
- `tools/` — the root watchdog, the debloat disable-set, and the root runner

Connect later with the standalone Samsung `sdb` tool (not committed; fetch your own —
see `README.md`):

```sh
./sdb/data/tools/sdb start-server
./sdb/data/tools/sdb connect 10.27.27.3:26101
./sdb/data/tools/sdb -s 10.27.27.3:26101 shell 0 applist
```

## 9. Going further: a (volatile) root path

The supported SDB surface cannot remove most preloads (see §3), so — for research
and completeness — a **volatile root path** was documented and reproduced on this
exact TV. It chains the public `SVE-2025-50109` package-name injection (a `uid=901(sdk)`
foothold) with the open-source, model-independent *archive-root* method, which abuses
Samsung's privileged signed-archive launcher by bind-mounting a replacement verification
key inside a private mount namespace.

Result: an authenticated `uid=0` root agent, verified by reading `/etc/shadow` and a
root-owned write test — with **no system files modified** and all staging removed.

- **`ROOTING-RESEARCH.md`** — mechanism, recon, evidence, impact, mitigations,
  **persistence** (§9.1 why on-device is impossible, §9.2 the host controller)
- **`paper/`** — the same work as a research paper
- **`evidence/`** — raw proof (root identity + `CapEff`, `getcap` inventory, SDB wire
  capture, the exact injection string, and the driver used)
- **`tools/`** — the persistent-root controller:
  - `tools/tv-rootwatch.sh` — re-roots the TV **and** re-applies the debloat after every reboot
  - `tools/tv-debloat-apply.sh` — the idempotent disable-set (kill-switch markers,
    TV Plus autorun flags, per-boot service masks) that the watchdog runs on each boot
  - `tools/tv-root-run.py` — run any command as root: `./tools/tv-root-run.py 'id'`

> This was done on my own hardware with Developer Mode enabled, purely to remove
> bloatware. Root is **volatile** (a reboot clears it) and nothing here is novel
> exploitation — it reproduces published work. Don't point it at hardware you don't own.
> **Turn Developer Mode back off when you're finished (§6).**

## 10. Persistent root (host-side)

The TV itself cannot hold root across a reboot: `/`, `/usr` and `/prd` are read-only
`vdfs` partitions, systemd's unit path contains no writable persistent directory, and
unsigned code will not run (see `ROOTING-RESEARCH.md` §9.1). So "persistence" is a
small watchdog on the PC that re-roots the TV the moment it comes back.

Installed as a **user** systemd service (no host root required):

```sh
systemctl --user status  tv-rootwatch.service     # active?
tail -f ~/.local/state/tv-root/rootwatch.log      # watch it re-root
./tools/tv-root-run.py 'id'                       # on-demand root command
```

It polls TCP `10.27.27.3:26101` every 5 s; whenever the TV returns after being
unreachable (i.e. it rebooted) it re-runs the archive-root exploit, confirms `uid=0`,
and re-applies the debloat disable-set (`tools/tv-debloat-apply.sh`) — about
**11 seconds** from device-up to rooted-and-debloated.

Because `/run` is tmpfs, the handful of services with no built-in kill switch are
masked per boot; the watchdog re-masks them every time. Everything else (`pkgcmd`
uninstalls and the `/opt` kill-switch markers) is already persistent on the TV.

To re-apply the disable-set by hand at any time:

```sh
./tools/tv-root-run.py "$(cat tools/tv-debloat-apply.sh)"
```

Remove it entirely with:

```sh
systemctl --user disable --now tv-rootwatch.service
rm ~/.config/systemd/user/tv-rootwatch.service
```
