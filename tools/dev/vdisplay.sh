#!/usr/bin/env bash
# Private headless Wayland compositor (mutter) with a 1280x720 virtual monitor.
# Why: a locked/idle desktop session throttles a normal Godot window to ~1 fps and makes screenshots and
# perf numbers useless. This gives Godot an unthrottled display that no one else is using.
#   tools/dev/vdisplay.sh start|stop|status
# Then run Godot with:  env -u DISPLAY WAYLAND_DISPLAY=wl-hr godot --display-driver wayland --rendering-driver opengl3 ...
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STATE="${TMPDIR:-/tmp}/hr-vdisplay"
mkdir -p "$STATE"
case "${1:-status}" in
  start)
    if [ -S "$RUNTIME/wl-hr" ]; then echo "wl-hr already running"; exit 0; fi
    XDG_RUNTIME_DIR="$RUNTIME" setsid nohup dbus-run-session -- mutter --headless --wayland --no-x11 \
      --virtual-monitor 1280x720@60 --wayland-display=wl-hr < /dev/null > "$STATE/mutter.log" 2>&1 &
    echo $! > "$STATE/mutter.pid"
    for _ in $(seq 1 60); do
      [ -S "$RUNTIME/wl-hr" ] && { echo "wl-hr ready"; exit 0; }
      sleep 0.25
    done
    echo "mutter did not come up:"; tail -20 "$STATE/mutter.log"; exit 1 ;;
  stop)
    [ -f "$STATE/mutter.pid" ] && kill "$(cat "$STATE/mutter.pid")" 2>/dev/null
    pkill -f "wayland-display=wl-hr" 2>/dev/null
    rm -f "$STATE/mutter.pid"; echo stopped ;;
  status)
    [ -S "$RUNTIME/wl-hr" ] && echo "running" || echo "stopped" ;;
esac
