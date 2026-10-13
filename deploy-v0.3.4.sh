#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/svo"
REPO="Elusivedamir/svo"
ARTIFACT="SVO-v0.3.4-debug"
DEST="$HOME/storage/shared/Download/SVO/v0.3.4"
command -v git >/dev/null || { echo 'Git is not installed'; exit 1; }
command -v gh >/dev/null || { echo 'GitHub CLI is not installed'; exit 1; }
test "$(git branch --show-current)" = main || { echo 'Current branch must be main'; exit 1; }
git remote get-url origin | grep -Fq 'Elusivedamir/svo' || { echo 'Wrong repository'; exit 1; }
for f in scripts/world_map.gd assets/map/terrain_v0.3.4.png assets/map/navigation_v0.3.4.png data/map_v0.3.4.json; do
  test -s "$f" || { echo "Missing patch file: $f"; exit 1; }
done
# Never tag an already-patched revision as stable.
if ! git show-ref --verify --quiet refs/tags/stable-v0.3.3; then
  git tag stable-v0.3.3 HEAD
  git push origin stable-v0.3.3
fi
git add scripts/world_map.gd assets/map/terrain_v0.3.4.png assets/map/navigation_v0.3.4.png \
 data/map_v0.3.4.json tools/author_water_v034.py README_STAGE03_4.md \
 export_presets.cfg .github/workflows/android-apk.yml deploy-v0.3.4.sh
if ! git diff --cached --quiet; then
  git commit -m "v0.3.4: tighten waterways and improve terrain clarity"
else
  echo "Nothing new to commit"
fi
git push origin main
SHA="$(git rev-parse HEAD)"
RUN_ID=""
for i in $(seq 1 40); do
  RUN_ID="$(gh run list -R "$REPO" --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  test -n "$RUN_ID" && break
  sleep 3
done
test -n "$RUN_ID" || { echo 'GitHub Actions run was not found'; exit 1; }
echo "Building: https://github.com/$REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R "$REPO" --exit-status
mkdir -p "$DEST"
rm -f "$DEST/SVO-v0.3.4-debug.apk"
for i in $(seq 1 12); do
  if gh run download "$RUN_ID" -R "$REPO" --name "$ARTIFACT" --dir "$DEST"; then break; fi
  sleep 5
done
APK="$DEST/SVO-v0.3.4-debug.apk"
test -s "$APK" || { echo 'APK not found'; exit 1; }
ls -lh "$APK"
echo 'Ready: Internal storage -> Download -> SVO -> v0.3.4'
