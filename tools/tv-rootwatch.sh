#!/usr/bin/env bash
# tv-rootwatch.sh - keep the Samsung Tizen TV rooted across reboots.
#
# Why this exists
# ---------------
# The QA55QEF1AULXL (Tizen 9.0, platform `rosel`) has no writable location on
# systemd's unit search path:
#
#   UnitPath=/etc/systemd/system /run/systemd/system /run/systemd/generator
#            /usr/lib/systemd/system /prd/usr/lib/systemd/system
#            /run/systemd/generator.late
#
# `/`, `/usr` and `/prd` are read-only `vdfs` partitions (and 100% full); the
# only entries that could be writable (`/run/...`) are tmpfs, so they are wiped
# on boot.  Tizen also refuses unsigned packages and the kernel's UEP blocks
# unsigned native executables.  Consequently there is no on-device boot hook we
# can safely use, and a reboot always drops root.
#
# The practical fix is to re-establish root from the host the moment the TV
# comes back.  sdbd (TCP 26101) only exists while the TV is running, so a
# reachable->unreachable->reachable transition means the TV rebooted; when that
# happens (and once at startup) this script runs the archive-root exploit again.
# Root is then available again with no manual steps.
#
# It is deliberately conservative: it never writes to the TV's read-only
# partitions and it only acts after confirming the device answered.  The whole
# thing is reversible with `systemctl --user disable --now tv-rootwatch`.
#
# Config: TV, HOST, SDB, RUNNER, INTERVAL, STATE_DIR, SDB_PORT
set -uo pipefail

TV="${TV:-10.27.27.3}"
SDB_PORT="${SDB_PORT:-26101}"
HOST="${HOST:-10.27.27.34}"
SDB="${SDB:-/home/swarn/dox/code/tv/sdb/data/tools/sdb}"
RUNNER="${RUNNER:-/home/swarn/dox/code/tv/tools/tv-root-run.py}"
DEBLOAT_APPLY="${DEBLOAT_APPLY:-/home/swarn/dox/code/tv/tools/tv-debloat-apply.sh}"
INTERVAL="${INTERVAL:-5}"          # presence poll interval, seconds
STATE_DIR="${STATE_DIR:-$HOME/.local/state/tv-root}"
LOG="${LOG:-$STATE_DIR/rootwatch.log}"
BOOTID_FILE="$STATE_DIR/last-rooted-bootid"

mkdir -p "$STATE_DIR"
log() { printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG"; }

# sdbd reachable?  (pure TCP probe; needs no TV cooperation)
tcp_up() {
  timeout 3 bash -c "exec 3<>/dev/tcp/$TV/$SDB_PORT" 2>/dev/null
}

# Run the archive-root exploit, re-apply the debloat disable-set, confirm uid 0.
# The debloat script is folded into the same root session so a boot costs one
# exploit run, not two.
root_command() {
  if [ -r "$DEBLOAT_APPLY" ]; then cat "$DEBLOAT_APPLY"; fi
  printf '\nid\ncat /proc/sys/kernel/random/boot_id\n'
}

root_tv() {
  "$SDB" connect "$TV:$SDB_PORT" >/dev/null 2>&1 || true
  TV="$TV" HOST="$HOST" SDB="$SDB" \
    python3 "$RUNNER" "$(root_command)" >"$STATE_DIR/last-run.json" 2>>"$LOG"
}

log "watchdog start tv=$TV host=$HOST poll=${INTERVAL}s"
up=0
while :; do
  if tcp_up; then
    if [ "$up" -eq 0 ]; then
      log "TV reachable at $TV:$SDB_PORT -> (re)rooting"
      if root_tv; then
        up=1
        bootid="$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
                    "$STATE_DIR/last-run.json" | head -1)"
        printf '%s' "$bootid" >"$BOOTID_FILE"
        printf '%s' "$(date -Is)" >"$STATE_DIR/last-rooted-at"
        if grep -q APPLY_OK "$STATE_DIR/last-run.json"; then
          log "root established (boot_id=${bootid:-unknown}); debloat disable-set applied"
        else
          log "root established (boot_id=${bootid:-unknown}); WARNING debloat apply unconfirmed"
        fi
      else
        log "root attempt failed; will retry"
        sleep 10
      fi
    fi
  else
    if [ "$up" -eq 1 ]; then
      log "TV unreachable (reboot/power off); will re-root when it returns"
    fi
    up=0
  fi
  sleep "$INTERVAL"
done
