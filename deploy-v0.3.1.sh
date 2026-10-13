#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/svo"
REPO="Elusivedamir/svo"
ARTIFACT="SVO-v0.3.1-debug"
DEST="$HOME/storage/shared/Download/SVO/v0.3.1"
command -v git >/dev/null || { echo 'git не установлен'; exit 1; }
command -v gh >/dev/null || { echo 'gh не установлен'; exit 1; }
test "$(git branch --show-current)" = main || { echo 'Пожалуйста, переключись на main'; exit 1; }
git remote get-url origin | grep -Fq 'Elusivedamir/svo' || { echo 'Неверный GitHub репозиторий'; exit 1; }
for f in scripts/world_map.gd assets/map/terrain_v0.3.1.png assets/map/navigation_v0.3.1.png data/map_v0.3.1.json; do
    test -s "$f" || { echo "Отсутствует файл: $f"; exit 1; }
done

git add scripts/world_map.gd assets/map/terrain_v0.3.1.png assets/map/navigation_v0.3.1.png \
 data/map_v0.3.1.json tools/make_nav_mask.py README_STAGE03_1.md \
 .github/workflows/android-apk.yml export_presets.cfg deploy-v0.3.1.sh
if ! git diff --cached --quiet; then
  git commit -m "v0.3.1: approved terrain and test ball with AStar navigation"
else
  echo 'Файлы версии уже в Git — повторять коммит не нужно.'
fi
git push origin main
SHA="$(git rev-parse HEAD)"
RUN_ID=''
for attempt in $(seq 1 45); do
  RUN_ID="$(gh run list -R "$REPO" --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  test -n "$RUN_ID" && break
  sleep 3
done
test -n "$RUN_ID" || { echo "Не найдена сборка: https://github.com/$REPO/actions"; exit 1; }
echo "Проверка и сборка APK: https://github.com/$REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R "$REPO" --exit-status
mkdir -p "$DEST"
rm -f "$DEST/SVO-v0.3.1-debug.apk"
for attempt in $(seq 1 15); do
  if gh run download "$RUN_ID" -R "$REPO" --name "$ARTIFACT" --dir "$DEST"; then break; fi
  echo "Публикация APK ещё не завершена ($attempt/15)"
  sleep 5
done
APK="$DEST/SVO-v0.3.1-debug.apk"
test -s "$APK" || { echo 'APK не найден после успешной сборки'; exit 1; }
ls -lh "$APK"
echo "Готово: Внутренняя память -> Download -> SVO -> v0.3.1"
echo 'Подтверди установку APK через Мои файлы Android.'
