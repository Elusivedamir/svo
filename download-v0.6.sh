#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
REPO="Elusivedamir/svo"
ARTIFACT="SVO-v0.6-debug"
DEST="$HOME/storage/shared/Download/SVO/v0.6"
command -v gh >/dev/null || { echo 'GitHub CLI is required'; exit 1; }
test -d "$HOME/storage/shared" || { echo 'Run termux-setup-storage first'; exit 1; }
RUN_ID="${1:-}"
if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(gh run list -R "$REPO" --workflow android-apk.yml --branch main --status success --limit 20 --json databaseId,displayTitle --jq '.[] | select(.displayTitle | startswith("v0.6:")) | .databaseId' | head -n 1)"
fi
test -n "$RUN_ID" || { echo 'Successful v0.6 build was not found'; exit 1; }
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
gh run download "$RUN_ID" -R "$REPO" --name "$ARTIFACT" --dir "$WORK_DIR"
APK="$WORK_DIR/SVO-v0.6-debug.apk"
test -s "$APK" || { echo 'v0.6 APK was not found in that run'; exit 1; }
mkdir -p "$DEST"
cp "$APK" "$DEST/SVO-v0.6-debug.apk"
ls -lh "$DEST/SVO-v0.6-debug.apk"
echo 'Ready: Internal storage -> Download -> SVO -> v0.6'
