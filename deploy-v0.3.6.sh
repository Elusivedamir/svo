#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SVO_PROJECT_DIR:-$HOME/svo}"
REPO="Elusivedamir/svo"
BASE_COMMIT="4d64283999b0ea6df96c5f6e7b78db2e4f5bfe67"
FILES=(
  assets/map/navigation_v0.3.6.png
  scripts/world_map.gd
  data/map_v0.3.6.json
  data/water_regions_v0.3.6.json
  tools/author_water_v036.py
  tools/test_navigation_v036.gd
  README_STAGE03_6.md
  shaders/terrain_clarity.gdshader
  assets/map/terrain_v0.3.4.png.import
  export_presets.cfg
  .github/workflows/android-apk.yml
  download-v0.3.6.sh
  deploy-v0.3.6.sh
)
fail() { echo "ERROR: $*" >&2; exit 1; }
for cmd in git gh sha256sum; do command -v "$cmd" >/dev/null || fail "$cmd is required"; done
test -d "$HOME/storage/shared" || fail 'Run termux-setup-storage first, then repeat this command'
test -d "$PROJECT_DIR/.git" || fail "Complete repository not found at $PROJECT_DIR"
# The source archive is checked before touching the user's repository.
(cd "$PATCH_DIR" && sha256sum -c SHA256SUMS)
cd "$PROJECT_DIR"
test "$(git branch --show-current)" = main || fail 'Switch to main before applying the patch'
git remote get-url origin | grep -Eq 'github\.com[:/]Elusivedamir/svo(\.git)?/?$' || fail 'Wrong origin repository'
git diff --quiet && git diff --cached --quiet || fail 'Save or commit current tracked changes before applying the patch'
gh auth status >/dev/null 2>&1 || fail 'GitHub CLI is not authenticated; use gh auth login'
git pull --ff-only origin main
test "$(git rev-parse HEAD)" = "$BASE_COMMIT" || fail 'main differs from the verified v0.3.5; do not overwrite it with this patch'
for file in "${FILES[@]}"; do
  test -s "$PATCH_DIR/$file" || fail "Missing patch file: $file"
  # Do not overwrite an unrelated local untracked file.
  if test -e "$file" && ! git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    cmp -s "$PATCH_DIR/$file" "$file" || fail "Untracked local file conflicts with patch: $file"
  fi
done
for file in assets/map/terrain_v0.3.4.png assets/map/navigation_v0.3.3.png assets/map/navigation_v0.3.4.png project.godot; do
  test -s "$file" || fail "Missing base project file: $file"
done
if git show-ref --verify --quiet refs/tags/stable-v0.3.5; then
  test "$(git rev-parse 'stable-v0.3.5^{commit}')" = "$BASE_COMMIT" || fail 'Existing stable-v0.3.5 tag refers to another version'
else
  git tag stable-v0.3.5 "$BASE_COMMIT"
fi
git push origin refs/tags/stable-v0.3.5
for file in "${FILES[@]}"; do
  mkdir -p "$(dirname "$file")"
  cp "$PATCH_DIR/$file" "$file"
done
chmod +x download-v0.3.6.sh deploy-v0.3.6.sh
git add -- "${FILES[@]}"
git commit -m 'v0.3.6: reopen northwest road and improve terrain clarity'
git push origin main
SHA="$(git rev-parse HEAD)"
RUN_ID=""
for i in $(seq 1 40); do
  RUN_ID="$(gh run list -R "$REPO" --workflow android-apk.yml --branch main --commit "$SHA" --event push --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  test -n "$RUN_ID" && break
  sleep 3
done
test -n "$RUN_ID" || fail 'Actions run was not found; see the repository Actions page'
echo "Building: https://github.com/$REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R "$REPO" --exit-status
bash "$PROJECT_DIR/download-v0.3.6.sh" "$RUN_ID"
echo 'Install SVO-v0.3.6-debug.apk, then check water and all three bridges on Samsung.'
