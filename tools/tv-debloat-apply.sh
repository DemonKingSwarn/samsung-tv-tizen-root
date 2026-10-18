#!/bin/sh
# tv-debloat-apply.sh - re-apply the TV debloat disable-set.
#
# Runs ON THE TV as root (via tools/tv-root-run.py, or automatically by
# tools/tv-rootwatch.sh after each boot).  Idempotent and safe to run repeatedly.
#
# It handles the parts of the debloat that pkgcmd cannot express, using Samsung's
# own mechanisms wherever they exist:
#   * persistent service "kill switch" markers that Samsung's units already test
#     with ConditionPathExists=!/opt/usr/share/systemd/system/<name>;
#   * TV Plus autorun flag files;
#   * per-boot systemd masks (/run is tmpfs, so these must be re-created on every
#     boot - which is exactly why the watchdog calls this script).
#
# NOTE: keep every list on a single line.  The staging path that delivers this
# script to the TV strips backslash-newline continuations.
R=/opt/usr/share/.debloat-report.txt
echo "--- debloat-apply $(date) ---" >>$R

MARKERS="canalysis-daemon pisa-service com.samsung.tv.context-aware-agent com.samsung.tv.context-aware-service com.samsung.tv.AICompanionAgent com.samsung.tv.bixby-prov com.samsung.tv.farfieldvoice com.samsung.tv.ondevice-voice com.samsung.tv.wakeupless com.samsung.tv.voiceid-service com.samsung.tv.ghdaemon"
FLAGS="/opt/usr/apps/tvplus_autorun_enable /opt/usr/apps/bstr_tvplus_mode"
MASKS="ambient-ua-agent.service data-service.service media-analytics-service.service org.tizen.tv.sp-kpi.service reminder-service.service pisa-service.socket com.samsung.tv.voiceassistant-music.service com.samsung.tv.iot-hub-control.service com.samsung.tv.iot-hub-control.path com.samsung.tv.iot-hub-control.vconf.service iot-hub-control-setup.service iot-hub-control-setup-factory.service"
STOPS="canalysis-service.service data-service.service media-analytics-service.service pisa-service.service org.tizen.tv.sp-kpi.service ambient-ua-agent.service reminder-service.service com.samsung.tv.context-aware-agent.service com.samsung.tv.context-aware-service.service com.samsung.tv.voiceassistant-music.service"

# 1. Samsung's built-in kill switches (persistent under /opt).
mkdir -p /opt/usr/share/systemd/system
for m in $MARKERS; do
  if [ ! -e "/opt/usr/share/systemd/system/$m" ]; then : >"/opt/usr/share/systemd/system/$m"; echo "marker $m" >>$R; fi
done

# 2. TV Plus autorun flags.
for f in $FLAGS; do
  if [ -e "$f" ]; then rm -f "$f"; echo "removed $f" >>$R; fi
done

# 3. Services with no built-in switch: mask them (per-boot).
for u in $MASKS; do
  if [ ! -e "/run/systemd/system/$u" ]; then ln -sf /dev/null "/run/systemd/system/$u"; echo "masked $u" >>$R; fi
done
systemctl daemon-reload 2>/dev/null

# 4. Stop anything still running.
for u in $STOPS; do systemctl stop "$u" 2>/dev/null; done

echo "done" >>$R
echo "APPLY_OK"
