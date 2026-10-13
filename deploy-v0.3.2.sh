#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/svo"
REPO="Elusivedamir/svo"
ARTIFACT="SVO-v0.3.2-debug"
DEST="$HOME/storage/shared/Download/SVO/v0.3.2"
command -v git >/dev/null || { echo "Нет Git"; exit 1; }
command -v gh >/dev/null || { echo "Нет GitHub CLI"; exit 1; }
test "$(git branch --show-current)" = "main" || { echo "Переключись на ветку main"; exit 1; }
git remote get-url origin | grep -Fq 'Elusivedamir/svo' || { echo "Неверный репозиторий"; exit 1; }
for f in assets/map/terrain_v0.3.2.png assets/map/navigation_v0.3.2.png scripts/world_map.gd data/map_v0.3.2.json; do
 test -s "$f" || { echo "Нет файла $f"; exit 1; }
done
# Protect exactly the previous playable source once.
if ! git show-ref --verify --quiet refs/tags/stable-v0.3.1-ball; then
  git tag stable-v0.3.1-ball
  git push origin stable-v0.3.1-ball
fi
git add assets/map/terrain_v0.3.2.png assets/map/navigation_v0.3.2.png scripts/world_map.gd data/map_v0.3.2.json tools/expand_four_sectors.py README_STAGE03_2.md export_presets.cfg .github/workflows/android-apk.yml deploy-v0.3.2.sh
if ! git diff --cached --quiet; then
 git commit -m "v0.3.2: fourfold world with traversable sector navigation"
else
 echo "Изменений нет, проверяю текущую сборку"
fi
git push origin main
SHA="$(git rev-parse HEAD)"
RUN_ID=""
for attempt in $(seq 1 45); do
 RUN_ID="$(gh run list -R "$REPO" --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
 test -n "$RUN_ID" && break
 sleep 3
done
test -n "$RUN_ID" || { echo "Не найдена сборка: https://github.com/$REPO/actions"; exit 1; }
echo "Сборка: https://github.com/$REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R "$REPO" --exit-status
mkdir -p "$DEST"
rm -f "$DEST/SVO-v0.3.2-debug.apk"
for n in $(seq 1 15); do
 if gh run download "$RUN_ID" -R "$REPO" --name "$ARTIFACT" --dir "$DEST"; then break; fi
 echo "Ожидаю публикацию APK..."
 sleep 5
done
APK="$DEST/SVO-v0.3.2-debug.apk"
test -s "$APK" || { echo "APK не найден"; exit 1; }
ls -lh "$APK"
echo "Готово: Мои файлы > Внутренняя память > Download > SVO > v0.3.2"
