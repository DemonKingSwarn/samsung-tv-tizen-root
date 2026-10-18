# Rooting a 2026 Samsung Tizen 9.0 TV through an SDB package-name injection

[![License: CC BY 4.0](https://img.shields.io/badge/License-CC_BY_4.0-blue.svg)](https://creativecommons.org/licenses/by/4.0/)
[![Paper](https://img.shields.io/badge/paper-Typst-239DAD.svg)](paper/main.typ)

Swarnaditya Singh (Independent) · DeepSeek V4.1 Flash (OpenCode)

A retail Samsung TV in Developer Mode exposes the SDB daemon on TCP 26101.
The daemon refuses a shell.
It still accepts one internal command: `0 appinstall tpk <name>`.
The daemon writes the name into a shell command without quoting.
A backtick substitution in the name runs as `uid=901(sdk)` with the `System` SMACK label.
That is SVE-2025-50109.

That shell cannot exec an unsigned native file.
It can pipe a script to `bash`.
It can also load managed code through the signed `/usr/bin/dotnet`.
That host carries `cap_setgid,cap_sys_admin`.
The managed payload makes a private mount namespace.
It bind-mounts its own key over the launcher key.
The signed launcher then runs the archive script as root.
A root agent calls back over an HMAC channel.
The controller accepts only `uid==euid==gid==egid==0`.
Root is verified.

The route is userland.
It needs no kernel bug.
It changes no system file.
Three adaptations were required on this model.

On this target, boot persistence is impossible on the device.
`/` and `/prd` are read-only.
systemd searches no writable unit directory.
A host watchdog re-arms root after each boot in about ten seconds.

Root removes 84 preinstalled packages.
The package count falls from 511 to 427.
No systemd unit fails.
The firmware's own kill-switch markers make the removals durable.

The reproduction covers one model and one firmware.
The persistence result belongs to this target.
These runs do not claim a general boot persistence method.

## Cite

```bibtex
@misc{singh2026tvtizenroot,
  author       = {Singh, Swarnaditya and {DeepSeek V4.1 Flash}},
  title        = {Rooting a 2026 {Samsung} {Tizen} 9.0 {TV} through an {SDB}
                  package-name injection},
  year         = {2026},
  month        = oct,
  howpublished = {GitHub},
  url          = {https://github.com/demonkingswarn/samsung-tv-tizen-root},
  note         = {License: CC BY 4.0}
}
```

## Compile

Go to the root of the repository.
Run `typst compile paper/main.typ`.
The PDF is `paper/main.pdf`.

## License

The paper uses the [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) license.
Read `LICENSE`.
The license covers `paper/main.typ` and `paper/refs.bib`.
The license also covers the PDF.
The license does not cover the code, the tooling, the inventories, or the evidence logs.

## Layout

- `paper/` contains the Typst source and the bibliography.
- `docs/` contains the practical debloat notes.
- `tools/` contains the host-side root watchdog, the idempotent debloat disable-set, and the root runner.
- `evidence/` contains the raw root proof, the unprivileged recon, the SDB wire capture, and the driver.
- `ROOTING-RESEARCH.md` is the long-form Markdown write-up of the same work.
- `samsung-tv-blocklist.txt` is a hosts-format blocklist.
- `classify-applist.py` is the classifier for the device `applist` output.
- `sdb/` is the vendored Samsung `sdb` tool.

`sdb/` is a proprietary Samsung binary.
`paper/main.pdf` is a build artifact.
Git ignores both.
