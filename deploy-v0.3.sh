#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/svo"
REPO="Elusivedamir/svo"
ARTIFACT="SVO-v0.3-debug"
DEST="$HOME/storage/shared/Download/SVO/v0.3"

command -v gh >/dev/null || { echo "Нет GitHub CLI: pkg install gh -y"; exit 1; }
command -v git >/dev/null || { echo "Нет Git: pkg install git -y"; exit 1; }

echo "Проверяю папку и GitHub..."
git remote get-url origin | grep -Fq 'Elusivedamir/svo' || { echo "Не тот репозиторий: остановлено"; exit 1; }
for f in scripts/world_map.gd scenes/world_map.tscn data/map_v0.3.json assets/map/terrain_v0.3.png; do
  test -s "$f" || { echo "Отсутствует файл: $f"; exit 1; }
done

git add scripts/main_menu.gd scripts/world_map.gd scenes/world_map.tscn \
        assets/map/terrain_v0.3.png data/map_v0.3.json \
        .github/workflows/android-apk.yml export_presets.cfg \
        README_STAGE03.md deploy-v0.3.sh tools/build_terrain.py
if ! git diff --cached --quiet; then
  git commit -m "v0.3: add clean playable map scene"
else
  echo "Изменения уже в коммите, продолжаю"
fi
git push origin main
SHA="$(git rev-parse HEAD)"
RUN_ID=""
for attempt in $(seq 1 35); do
  RUN_ID="$(gh run list -R "$REPO" --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  [ -n "$RUN_ID" ] && break
  sleep 3
done
[ -n "$RUN_ID" ] || { echo "Сборка не появилась: https://github.com/$REPO/actions"; exit 1; }
echo "Открыть сборку: https://github.com/$REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R "$REPO" --exit-status

mkdir -p "$DEST"
rm -f "$DEST/SVO-v0.3-debug.apk"
for attempt in $(seq 1 18); do
  if gh run download "$RUN_ID" -R "$REPO" --name "$ARTIFACT" --dir "$DEST"; then
    break
  fi
  echo "Ожидаю APK ($attempt/18)"
  sleep 5
done
APK="$DEST/SVO-v0.3-debug.apk"
test -s "$APK" || { echo "APK не найден. Открой ссылку на сборку выше"; exit 1; }
ls -lh "$APK"
echo "Готово! APK: Мои файлы -> Внутренняя память -> Download -> SVO -> v0.3"
echo "Установку подтверди в Android. При конфликте временных ключей удалить старую тестовую версию."
