#!/usr/bin/env bash
# The Halcyon dev runner. Usage: ./dev.sh <command> [args]
#   import            import assets / refresh the class cache (run after adding files with class_name)
#   check             parse-check every script (headless)
#   test [filter]     run tests/test_*.gd (optionally only files containing <filter>)
#   run [-- args]     run the game windowed
#   shot <scene> <out.png> [frame]   windowed screenshot of a dev scene (--scene=<scene>)
#   smoke [frames]    boot the main scene headless for N frames, fail on script errors
#   export            Linux release build to build/linux + smoke run of the binary
#   soak [n]          generate n floors per floor def and check fairness/solvability
#   floors [seed]     headless: a bot walks every floor (both truths) end to end; fails on script errors
set -u
cd "$(dirname "$0")"
# Godot binary: $GODOT, else the path in ./.godot_bin (git-ignored, one line), else `godot` on PATH.
if [ -z "${GODOT:-}" ]; then
  if [ -f .godot_bin ]; then GODOT="$(head -n1 .godot_bin)"; else GODOT="godot"; fi
fi
# Windowed runs go through a private virtual display unless HR_REAL_DISPLAY=1 (a locked session throttles
# a normal window to ~1 fps).
gwin() {
  if [ "${HR_REAL_DISPLAY:-0}" = "1" ]; then
    "$GODOT" --path . "$@"
  else
    tools/dev/vdisplay.sh start >/dev/null
    env -u DISPLAY WAYLAND_DISPLAY=wl-hr "$GODOT" --path . --display-driver wayland --rendering-driver opengl3 "$@"
  fi
}
# Refresh the global class cache when a script was added/changed since the last import (new class_names
# are otherwise invisible to the parser, which shows up as bogus "does not compile" errors).
ensure_import() {
  local cache=".godot/global_script_class_cache.cfg"
  if [ ! -f "$cache" ] || [ -n "$(find . -path ./.godot -prune -o -path ./tools/mcp -prune -o -name '*.gd' -newer "$cache" -print -quit)" ]; then
    "$GODOT" --headless --path . --import >/dev/null 2>&1
  fi
}
cmd="${1:-}"; shift || true
case "$cmd" in check|test|soak|smoke|shot|run|floors) ensure_import ;; esac
case "$cmd" in
  import)
    "$GODOT" --headless --path . --import 2>&1 | grep -v -E "^(Godot Engine|Vulkan|OpenGL)" ;;
  check)
    "$GODOT" --headless --path . res://tests/test_runner.tscn -- --filter=compile 2>&1 | grep -v -E "^(Godot Engine|Vulkan|OpenGL)" | tail -80 ;;
  test)
    "$GODOT" --headless --path . res://tests/test_runner.tscn -- --filter="${1:-}" 2>&1 | grep -v -E "^(Godot Engine|Vulkan|OpenGL)" ;;
  run)
    gwin "$@" ;;
  shot)
    scene="${1:?scene}"; out="${2:?out.png}"; frame="${3:-90}"
    gwin --resolution 1280x720 -- --scene="$scene" --shot="$out" --shot-frame="$frame" "${@:4}" 2>&1 | grep -v -E "^(Godot Engine|Vulkan|OpenGL|WARNING: (Can.t obtain|xdg-toplevel)|     at: init)" ;;
  smoke)
    "$GODOT" --headless --path . -- --quit-frame="${1:-120}" 2>&1 | grep -v -E "^(Godot Engine|Vulkan|OpenGL)" ;;
  export)
    # Linux release build + a smoke run of the exported binary (catches missing files / stripped scripts).
    mkdir -p build/linux
    "$GODOT" --headless --path . --export-release "Linux" build/linux/halcyon.x86_64 2>&1 | grep -v -E "^(Godot Engine|Vulkan|OpenGL)" | tail -15
    ls -la build/linux/ | tail -4
    out=$(timeout 120 build/linux/halcyon.x86_64 --headless --quit-after 400 2>&1 | grep -v -E "^(Godot Engine|Vulkan|OpenGL)")
    if echo "$out" | grep -q -E "SCRIPT ERROR|ERROR:|Failed to load"; then echo "EXPORT SMOKE FAILED"; echo "$out" | head -15; exit 1; else echo "export smoke ok"; fi ;;
  soak)
    "$GODOT" --headless --path . res://tests/test_runner.tscn -- --filter=soak --soak="${1:-100}" 2>&1 | grep -v -E "^(Godot Engine|Vulkan|OpenGL)" ;;
  floors)
    seed="${1:-5}"; fails=0
    for f in boiler natatorium blue yellow units lobby; do
      for t in 0 1; do
        out=$("$GODOT" --headless --path . --fixed-fps 60 -- --scene=floor --floor=$f --seed=$seed --truth=$t --bot=floor_walk --bot-quit --quit-frame=36000 2>&1 | grep -v -E "^(Godot Engine|Vulkan|OpenGL)|ObjectDB|resources still|at: (cleanup|clear)")
        if echo "$out" | grep -q -E "SCRIPT ERROR|ERROR:|stuck|did not open|no path|left the main"; then fails=$((fails+1)); echo "FAIL $f truth=$t"; echo "$out" | head -12; else echo "ok   $f truth=$t: $(echo "$out" | grep -E 'BOT:' | tail -1 | cut -c1-150)"; fi
      done
    done
    echo "floors failed: $fails"; exit $fails ;;
  *)
    sed -n '2,13p' "$0"; exit 1 ;;
esac
