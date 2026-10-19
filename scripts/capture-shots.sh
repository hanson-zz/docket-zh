#!/usr/bin/env bash
#
# Photographs the app's real detail panels, and the shelf itself, for the
# README.
#
# Builds the Shots target, which puts each view in a real window on a real
# display and prints where it landed; this script then screenshots that region.
# The round trip exists because these surfaces are behind-window materials -
# an NSVisualEffectView for a panel, macOS 26 glass for the shelf - and neither
# has anything to sample unless the window is genuinely on screen, so an
# offscreen render is not the same picture.
#
# Every capture is reported with what it actually shows: `live` for readings
# taken from this machine, this network or this clock, `sample` for a widget's
# own preview values, and `empty` for a panel's honest "nothing is connected"
# state. Anything that is not `live` has to be labelled wherever the image is
# used.
#
# Must be run on a Mac, sitting at a real display that is awake and unlocked.
# Screen Recording permission belongs to whatever runs this - Terminal, iTerm,
# your editor - not to the Shots binary, so the first run may capture blank
# images until that app is ticked in System Settings > Privacy & Security >
# Screen & System Audio Recording, and restarted.
#
# The run takes a few minutes: two panels wait on a network fetch, and one
# draws a live graph from a rolling one-second sampler, which is waited out
# rather than shipping a graph with four points in it. Everything sits above
# the rest of the display while it is captured, so leave the machine alone
# until it prints its summary.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# SHOTS_LANG picks the interface language the shots are taken in: zh-Hans (the
# default, the app's own source language) or en. Each language has its own
# folder under docs/images, which is what README.md and README.en.md read.
SHOTS_LANG="${SHOTS_LANG:-zh-Hans}"
case "$SHOTS_LANG" in
  zh|zh-Hans|zh_CN) SHOTS_LANG="zh-Hans"; LANG_DIR="zh"; LOCALE="zh_CN" ;;
  en|en-US|en_US)   SHOTS_LANG="en";      LANG_DIR="en"; LOCALE="en_US" ;;
  *) printf 'capture-shots: SHOTS_LANG must be zh-Hans or en, not %s\n' "$SHOTS_LANG" >&2; exit 1 ;;
esac
export SHOTS_LANG

# SHOTS_OUT sends the images somewhere other than the README's folder, for
# looking at a change before it replaces what is published.
OUT_DIR="${SHOTS_OUT:-$ROOT/docs/images/$LANG_DIR}"
DERIVED="${TMPDIR:-/tmp}/docket-shots-build"

fail() { printf 'capture-shots: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "macOS only - this drives the window server."
[ -z "${SSH_CONNECTION:-}" ] || fail "run this at the Mac itself; an SSH session has no display to capture."
command -v xcodebuild >/dev/null || fail "xcodebuild not found - install the Xcode command line tools."
command -v screencapture >/dev/null || fail "screencapture not found."

# 双语工作流先单独构建一次，拍摄阶段只切换资源；本机直接运行仍会先构建。
if [ "${SHOTS_SKIP_BUILD:-0}" != 1 ]; then
  echo "capture-shots: building the Shots target…"
  # -target rather than -scheme, so this does not depend on a generated scheme -
  # but xcodebuild refuses -derivedDataPath without one, so the build lands in the
  # project's usual location and the binary is found by asking where that is.
  xcodebuild -project "$ROOT/Docket.xcodeproj" \
             -target Shots \
             -configuration Release \
             SWIFT_OPTIMIZATION_LEVEL=-Onone build >"$DERIVED.log" 2>&1 \
    || { tail -40 "$DERIVED.log" >&2; fail "build failed; the full log is at $DERIVED.log"; }
fi

PRODUCTS=$(xcodebuild -project "$ROOT/Docket.xcodeproj" -target Shots \
                      -configuration Release -showBuildSettings 2>/dev/null \
           | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
BIN="$PRODUCTS/Shots"
[ -x "$BIN" ] || fail "built, but no executable at $BIN"

mkdir -p "$OUT_DIR"

# The Shots tool is a bare executable, not an app bundle, so the String Catalog
# the app ships compiled into its Resources is not next to it. Bundle.main for
# a bare executable is the folder it sits in, which is where an en.lproj is
# looked for. English gets one, written from Localizable.xcstrings; Chinese,
# the source language, needs none, and any left over from an English run is
# removed so a Chinese run cannot fall back to it.
rm -rf "$PRODUCTS"/*.lproj

# The pictures the app bundles as plain resources (the red panda the AI
# assistant, Water, the virtual pet and the Slacker Clock draw, the radio) are
# looked up with Bundle.main too, so they go beside the tool the same way, flat,
# as they sit in the app's Resources. Without them those views draw their
# fallback glyphs instead of the art.
for folder in Pet Water Radio Slacker AppIcons; do
  [ -d "$ROOT/Resources/$folder" ] && cp -f "$ROOT/Resources/$folder"/*.png "$PRODUCTS/" 2>/dev/null || true
done

if [ "$SHOTS_LANG" = "en" ]; then
  command -v python3 >/dev/null || fail "python3 not found; it writes the English strings for the tool."
  mkdir -p "$PRODUCTS/en.lproj"
  python3 "$ROOT/scripts/strings-from-catalog.py" \
          "$ROOT/Resources/Localization/Localizable.xcstrings" en \
          "$PRODUCTS/en.lproj/Localizable.strings" \
    || fail "could not write the English strings."
  plutil -lint "$PRODUCTS/en.lproj/Localizable.strings" >/dev/null \
    || fail "the English strings written for the tool do not parse."
fi

# Two named pipes rather than a sleep: the tool prints a frame, waits, and only
# tears the window down once this script says the capture came back. A fixed
# wait is either too short on a busy machine or wasted on an idle one, and a
# capture that lands early is silently half a window.
PIPES="$(mktemp -d "${TMPDIR:-/tmp}/docket-shots.XXXXXX")"
FRAMES="$PIPES/frames"
ACK="$PIPES/ack"
mkfifo "$FRAMES" "$ACK"

SHOTS_PID=""
cleanup() {
  [ -n "$SHOTS_PID" ] && kill -KILL "$SHOTS_PID" 2>/dev/null || true
  rm -rf "$PIPES"
}
trap cleanup EXIT

# Opened read-write so the tool's stdin never sees EOF between acknowledgements.
exec 3<>"$ACK"
"$BIN" <&3 >"$FRAMES" &
SHOTS_PID=$!
exec 4<"$FRAMES"

WRITTEN=()
FAILED=()

FRAME_TIMEOUT="${SHOTS_FRAME_TIMEOUT:-180}"
case "$FRAME_TIMEOUT" in
  ''|*[!0-9]*) fail "SHOTS_FRAME_TIMEOUT must be a positive number of seconds." ;;
esac
[ "$FRAME_TIMEOUT" -gt 0 ] || fail "SHOTS_FRAME_TIMEOUT must be greater than zero."
LAST_FRAME="startup"
while :; do
  # macOS 自带 Bash 的 read -t 对 FIFO 不能可靠限时，使用 select 的绝对期限。
  if frame=$(python3 "$ROOT/scripts/read-shot-frame.py" "$FRAME_TIMEOUT" <&4); then
    read -r name x y w h source <<< "$frame"
    LAST_FRAME="$name"
  else
    status=$?
    if [ "$status" = 124 ]; then
      kill -KILL "$SHOTS_PID" 2>/dev/null || true
      fail "no frame for $FRAME_TIMEOUT seconds after $LAST_FRAME; see the last prepare/measure log."
    fi
    break
  fi
  # A tool that predates the source column still gets its images captured;
  # only the label is unknown.
  source="${source:-unknown}"
  dest="$OUT_DIR/$name.png"
  rm -f "$dest"
  screencapture -x -R "$x,$y,$w,$h" "$dest" || true
  printf 'ok\n' >&3

  if [ -s "$dest" ]; then
    # Name and provenance travel together; no shot name contains a colon.
    WRITTEN+=("$name:$source")
    printf 'capture-shots: %-16s %sx%s pt  %s\n' "$name" "$w" "$h" "$source"
  else
    FAILED+=("$name")
    printf 'capture-shots: %-16s NO IMAGE\n' "$name" >&2
  fi
done

wait "$SHOTS_PID" || fail "the Shots tool exited badly; nothing further was captured."
SHOTS_PID=""

echo
echo "capture-shots: wrote ${#WRITTEN[@]} image(s) to $OUT_DIR/"
NOT_LIVE=0
for entry in "${WRITTEN[@]:-}"; do
  [ -n "$entry" ] || continue
  name="${entry%%:*}"
  source="${entry#*:}"
  [ "$source" = "live" ] || NOT_LIVE=$((NOT_LIVE + 1))
  # `|| true`: a file sips cannot read reports no size rather than taking the
  # whole summary down with it - the check that matters already ran above.
  pw=""; ph=""
  read -r pw ph < <(sips -g pixelWidth -g pixelHeight "$OUT_DIR/$name.png" 2>/dev/null \
                    | awk '$1=="pixelWidth:"{w=$2} $1=="pixelHeight:"{h=$2}
                           END{if (w ~ /^[0-9]+$/ && h ~ /^[0-9]+$/) print w, h}') || true
  printf '  %-34s %8sx%-8s %s\n' "$name.png" "${pw:-?}" "${ph:-?}" "$source"
done

if [ "$NOT_LIVE" -gt 0 ]; then
  echo
  printf 'capture-shots: %s image(s) above are not live readings. Say so wherever\n' "$NOT_LIVE"
  echo "               they are used: an unlabelled sample reads as a real one."
fi

if [ "${#FAILED[@]}" -gt 0 ] && [ -n "${FAILED[0]:-}" ]; then
  echo
  printf 'capture-shots: %s capture(s) produced nothing: %s\n' "${#FAILED[@]}" "${FAILED[*]}" >&2
  echo "capture-shots: a blank or missing file almost always means Screen Recording" >&2
  echo "               permission is missing for the app running this script." >&2
  exit 1
fi

if [ "${#WRITTEN[@]}" -eq 0 ]; then
  fail "the tool printed no frames at all; check $DERIVED.log and that a display is awake."
fi
