#!/usr/bin/env python3
"""Sort `sdb shell 0 applist` output into safe-to-remove and never-touch.

Capture the list first:

    sdb -s <TV_IP>:26101 shell 0 applist > applist.txt
    python3 classify-applist.py applist.txt

Classification rules (see README Part 5):

    org.tizen.*                 Tizen platform          NEVER remove
    com.samsung.*               Samsung platform        NEVER remove
    <10 alphanumerics>.<name>   Samsung store app       usually removable
    anything else               misc system service     NEVER remove

Four packages match the store-app pattern but are infrastructure; they are
flagged separately and must not be removed.

Nothing here talks to the TV or changes anything -- it only reads a text file.
"""
import argparse
import re
import sys
from collections import OrderedDict

STORE_RE = re.compile(r"^[A-Za-z0-9]{10}\.")
ENTRY_RE = re.compile(r"'(.*?)'\s*'(.*?)'")

# Store-shaped IDs that are actually platform infrastructure.
INFRA_EXACT = {
    "ZODRT12q2l.WebAccountExtension",
    "aQjWjLsPaO.MultiScreenWebLauncher",
    "adplatform.ADPlayer",
}
INFRA_PREFIX = ("30IKH0OX8U.",)

# Looks like removable duplication; is not.
DO_NOT_REMOVE = {"org.tizen.netflixlowmem"}


def is_infra(app_id: str) -> bool:
    return app_id in INFRA_EXACT or app_id.startswith(INFRA_PREFIX)


def classify(app_id: str) -> str:
    if app_id.startswith("org.tizen."):
        return "tizen"
    if app_id.startswith("com.samsung."):
        return "samsung"
    if STORE_RE.match(app_id) or app_id.startswith("adplatform."):
        return "store"
    return "misc"


def parse(path: str):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = ENTRY_RE.search(line)
            if m:
                rows.append((m.group(1), m.group(2)))
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description="Classify Tizen applist output")
    ap.add_argument("applist", help="file containing 'sdb shell 0 applist' output")
    ap.add_argument("--ids-only", action="store_true",
                    help="print just the removable package IDs, one per line")
    args = ap.parse_args()

    try:
        rows = parse(args.applist)
    except OSError as e:
        print(f"Could not read {args.applist}: {e}", file=sys.stderr)
        return 2

    if not rows:
        print("No application entries found.", file=sys.stderr)
        print("Expected lines like:  'Netflix'  'RN1MCdNq8t.Netflix'", file=sys.stderr)
        return 2

    buckets = OrderedDict((k, []) for k in ("store", "tizen", "samsung", "misc"))
    for name, app_id in rows:
        buckets[classify(app_id)].append((name, app_id))

    removable = [(n, a) for n, a in buckets["store"] if not is_infra(a)]
    infra = [(n, a) for n, a in buckets["store"] if is_infra(a)]

    if args.ids_only:
        # Several apps can share one package ID (e.g. Disney+ and its preview
        # service). Uninstall takes the package ID, so emit each only once.
        seen = sorted({app_id.split(".")[0] for _, app_id in removable})
        for pkg_id in seen:
            print(pkg_id)
        return 0

    print(f"\n{len(rows)} packages found in {args.applist}\n")
    print(f"  Removable store apps : {len(removable)}")
    print(f"  Infrastructure       : {len(infra)}  (store-shaped, DO NOT remove)")
    print(f"  org.tizen.* platform : {len(buckets['tizen'])}  (never remove)")
    print(f"  com.samsung.* platform: {len(buckets['samsung'])}  (never remove)")
    print(f"  Misc system services : {len(buckets['misc'])}  (never remove)")

    print("\n" + "=" * 62)
    print("REMOVABLE -- store apps")
    print("=" * 62)
    print("Remove with:  sdb -s <TV_IP>:26101 uninstall <PACKAGE ID>")
    print("Note the package ID is the part BEFORE the first dot.\n")
    print(f"  {'App':<30} {'Package ID':<14} App ID")
    print(f"  {'-'*30} {'-'*14} {'-'*30}")
    for name, app_id in sorted(removable, key=lambda x: x[1]):
        print(f"  {(name or '(no name)'):<30} {app_id.split('.')[0]:<14} {app_id}")

    if infra:
        print("\n" + "=" * 62)
        print("DO NOT REMOVE -- looks like a store app, is infrastructure")
        print("=" * 62)
        for name, app_id in sorted(infra, key=lambda x: x[1]):
            print(f"  {(name or '(no name)'):<30} {app_id}")

    flagged = [a for _, a in rows if a in DO_NOT_REMOVE]
    if flagged:
        print("\n" + "=" * 62)
        print("SPECIFIC WARNING")
        print("=" * 62)
        for app_id in flagged:
            print(f"  {app_id}")
        print("  Low-memory Netflix fallback. Looks redundant; removing it can")
        print("  stop Netflix launching entirely. Leave it alone.")

    print("\nPlatform packages are hidden. Re-run with --ids-only for a bare list.")
    print("Full reference: reference/UE55NU7400-tizen4.0.md\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
