#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 || ( "$1" != chrome && "$1" != edge ) || ! "$2" =~ ^[a-p]{32}$ ]]; then
  echo "Usage: bash install-host.sh chrome|edge EXTENSION_ID /path/to/Dockling.app" >&2
  exit 1
fi
if [[ "$1" == chrome ]]; then
  browser_support="Google/Chrome"
else
  browser_support="Microsoft Edge"
fi
helper_source="$3/Contents/MacOS/DocklingBrowserHost"
test -x "$helper_source"
host_dir="$HOME/Library/Application Support/Dockling/BrowserHost"
manifest_dir="$HOME/Library/Application Support/$browser_support/NativeMessagingHosts"
helper="$host_dir/dockling-$1-host"
mkdir -p "$host_dir" "$manifest_dir"
install -m 700 "$helper_source" "$helper"
/usr/bin/osascript -l JavaScript - "$helper" "$2" <<'JXA' > "$manifest_dir/com.docket_zh.time_insights.json"
function run(args) {
  return JSON.stringify({
    name: "com.docket_zh.time_insights",
    description: "Dockling Time Insights",
    path: args[0],
    type: "stdio",
    allowed_origins: ["chrome-extension://" + args[1] + "/"]
  });
}
JXA
