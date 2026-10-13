#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/svo"
REPO="Elusivedamir/svo"
ARTIFACT="SVO-v0.3.3-debug"
DEST="$HOME/storage/shared/Download/SVO/v0.3.3"
command -v git >/dev/null || { echo 'Нет git'; exit 1; }
command -v gh >/dev/null || { echo 'Нет gh'; exit 1; }
test "$(git branch --show-current)" = "main" || { echo 'Нужна ветка main'; exit 1; }
git remote get-url origin | grep -Fq 'Elusivedamir/svo' || { echo 'Неверный репозиторий'; exit 1; }
for f in assets/map/terrain_v0.3.3.png assets/map/navigation_v0.3.3.png scripts/world_map.gd data/map_v0.3.3.json; do
  test -s "$f" || { echo "Файл отсутствует: $f"; exit 1; }
done
# Preserve exact prior HEAD before the new commit, on first deployment only.
if ! git show-ref --verify --quiet refs/tags/stable-v0.3.2; then
  git tag stable-v0.3.2
  git push origin stable-v0.3.2
fi
git add scripts/world_map.gd assets/map/terrain_v0.3.3.png assets/map/navigation_v0.3.3.png \
 data/map_v0.3.3.json tools/author_unique_nav.py README_STAGE03_3.md \
 export_presets.cfg .github/workflows/android-apk.yml deploy-v0.3.3.sh
if ! git diff --cached --quiet; then
  git commit -m 'v0.3.3: unique continuous landscape and mapped obstacles'
else
  echo 'Коммит не требуется'
fi
git push origin main
SHA="$(git rev-parse HEAD)"
RUN_ID=''
for i in $(seq 1 40); do
  RUN_ID="$(gh run list -R "$REPO" --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  test -n "$RUN_ID" && break
  sleep 3
done
test -n "$RUN_ID" || { echo 'Сборка пока не найдена'; exit 1; }
echo "GitHub Actions: https://github.com/$REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R "$REPO" --exit-status
mkdir -p "$DEST"
rm -f "$DEST/SVO-v0.3.3-debug.apk"
for n in $(seq 1 12); do
  if gh run download "$RUN_ID" -R "$REPO" --name "$ARTIFACT" --dir "$DEST"; then break; fi
  echo "Ожидание APK: $n / 12"
  sleep 5
done
APK="$DEST/SVO-v0.3.3-debug.apk"
test -s "$APK" || { echo 'APK не найден'; exit 1; }
ls -lh "$APK"
echo 'Готово: Мои файлы -> Внутренняя память -> Download -> SVO -> v0.3.3'
