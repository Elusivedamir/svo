#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SVO_PROJECT_DIR:-$HOME/svo}"
REPO="Elusivedamir/svo"
BASE_COMMIT="40763255e8c779127b4d60c742b5b9d1bec1f216"
FILES=(
  scripts/world_map.gd
  tools/test_camera_v04.gd
  tools/camera_v04_probe.gd
  tools/test_squad_v05.gd
  tools/squad_v05_probe.gd
  assets/map/navigation_v0.5.1.png
  data/bridge_corridors_v0.5.1.json
  tools/author_bridge_v051.py
  tools/test_bridge_v051.gd
  README_STAGE05_1.md
  export_presets.cfg
  .github/workflows/android-apk.yml
  download-v0.5.1.sh
  deploy-v0.5.1.sh
)
fail() { echo "ERROR: $*" >&2; exit 1; }
for cmd in git gh sha256sum cmp mktemp; do command -v "$cmd" >/dev/null || fail "$cmd is required"; done
test -d "$HOME/storage/shared" || fail 'Run termux-setup-storage first, then repeat this command'
test -d "$PROJECT_DIR/.git" || fail "Complete repository not found at $PROJECT_DIR"
# Verify the complete source archive before changing the user's repository.
(cd "$PATCH_DIR" && sha256sum -c SHA256SUMS)
for file in "${FILES[@]}"; do
  test -s "$PATCH_DIR/$file" || fail "Missing patch file: $file"
done
cd "$PROJECT_DIR"
test "$(git branch --show-current)" = main || fail 'Switch to main before applying the patch'
git remote get-url origin | grep -Eq 'github\.com[:/]Elusivedamir/svo(\.git)?/?$' || fail 'Wrong origin repository'
git diff --quiet && git diff --cached --quiet || fail 'Save or commit current tracked changes before applying the patch'
# Check collisions before any fast-forward or copying can touch the working tree.
for file in "${FILES[@]}"; do
  if test -e "$file" && ! git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    cmp -s "$PATCH_DIR/$file" "$file" || fail "Untracked local file conflicts with patch: $file"
  fi
done
for file in assets/map/terrain_v0.3.4.png assets/map/navigation_v0.3.6.png shaders/terrain_clarity.gdshader tools/test_navigation_v036.gd data/water_regions_v0.3.6.json project.godot; do
  test -s "$file" || fail "Missing base project file: $file"
done
gh auth status >/dev/null 2>&1 || fail 'GitHub CLI is not authenticated; use gh auth login'
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
commit_has_patch() {
  local commit="$1" file
  git merge-base --is-ancestor "$BASE_COMMIT" "$commit" || return 1
  for file in "${FILES[@]}"; do
    git show "$commit:$file" > "$WORK_DIR/file" 2>/dev/null || return 1
    cmp -s "$PATCH_DIR/$file" "$WORK_DIR/file" || return 1
  done
}
git fetch origin main
REMOTE_COMMIT="$(git rev-parse FETCH_HEAD)"
LOCAL_COMMIT="$(git rev-parse HEAD)"
if test "$REMOTE_COMMIT" != "$BASE_COMMIT" && ! commit_has_patch "$REMOTE_COMMIT"; then
  fail 'main differs from the verified v0.4 and this exact v0.5.1 patch; repository was not overwritten'
fi
if test "$LOCAL_COMMIT" != "$REMOTE_COMMIT"; then
  git merge-base --is-ancestor "$LOCAL_COMMIT" "$REMOTE_COMMIT" || fail 'Local main differs from GitHub; save those commits before applying this patch'
  git merge --ff-only "$REMOTE_COMMIT"
fi
test "$(git rev-parse HEAD)" = "$REMOTE_COMMIT" || fail 'Local main did not reach the verified GitHub commit'
if test "$REMOTE_COMMIT" = "$BASE_COMMIT"; then
  if git show-ref --verify --quiet refs/tags/stable-v0.4; then
    test "$(git rev-parse 'stable-v0.4^{commit}')" = "$BASE_COMMIT" || fail 'Existing stable-v0.4 tag refers to another version'
  else
    git tag stable-v0.4 "$BASE_COMMIT"
  fi
  git push origin refs/tags/stable-v0.4
  for file in "${FILES[@]}"; do
    mkdir -p "$(dirname "$file")"
    cp "$PATCH_DIR/$file" "$file"
  done
  chmod +x download-v0.5.1.sh deploy-v0.5.1.sh
  git add -- "${FILES[@]}"
  git commit -m 'v0.5.1: open junction bridge and add selectable infantry squad'
  git push origin main
else
  # A repeated invocation must resume the exact pushed patch, not make another commit.
  echo 'This exact v0.5.1 patch is already on GitHub; continuing with its APK build.'
fi
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
bash "$PROJECT_DIR/download-v0.5.1.sh" "$RUN_ID"
echo 'Install SVO-v0.5.1-debug.apk, then check squad selection, movement, stop, camera, water and bridges on Samsung.'
