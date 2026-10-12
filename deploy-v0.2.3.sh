#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/svo"
REPO="Elusivedamir/svo"
ARTIFACT="SVO-v0.2.3-debug"
DEST="$HOME/storage/shared/Download/SVO/v0.2.3"

for command in git gh; do
  command -v "$command" >/dev/null || { echo "Не установлена утилита $command"; exit 1; }
done

git add scripts/main_menu.gd scripts/music_manager.gd scripts/menu_atmosphere.gd \
  assets/audio/frontline_evening_theme.ogg export_presets.cfg \
  .github/workflows/android-apk.yml README_v0.2.3.txt deploy-v0.2.3.sh
if ! git diff --cached --quiet; then
  git commit -m "v0.2.3: restore menu and smoke-test runtime"
else
  echo "Изменения уже зафиксированы, новый коммит не нужен"
fi
git push origin main
SHA="$(git rev-parse HEAD)"
RUN_ID=""
for i in $(seq 1 40); do
  RUN_ID="$(gh run list -R "$REPO" --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  [ -n "$RUN_ID" ] && break
  sleep 3
done
[ -n "$RUN_ID" ] || { echo "Не удалось найти сборку: https://github.com/$REPO/actions"; exit 1; }
echo "Сборка: https://github.com/$REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R "$REPO" --exit-status
mkdir -p "$DEST"
rm -f "$DEST/SVO-v0.2.3-debug.apk"
for i in $(seq 1 15); do
  if gh run download "$RUN_ID" -R "$REPO" --name "$ARTIFACT" --dir "$DEST"; then break; fi
  echo "Ожидаю APK ($i/15)"
  sleep 5
done
APK="$DEST/SVO-v0.2.3-debug.apk"
test -s "$APK" || { echo "APK не найден после сборки"; exit 1; }
ls -lh "$APK"
echo "Готово: Мои файлы -> Внутренняя память -> Download -> SVO -> v0.2.3"
