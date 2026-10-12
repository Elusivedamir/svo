#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/svo"
if ! command -v gh >/dev/null 2>&1; then
  echo "Нет утилиты gh. Установи: pkg install gh -y" >&2
  exit 1
fi

git add project.godot export_presets.cfg scripts/music_manager.gd scripts/menu_atmosphere.gd scripts/main_menu.gd \
  assets/audio/frontline_evening_theme.ogg .github/workflows/android-apk.yml README_v0.2.1.txt deploy-v0.2.1.sh

if ! git diff --cached --quiet; then
  git commit -m "v0.2.1: center settings, graphic options and original soundtrack"
else
  echo "Коммит не нужен: новые файлы уже в репозитории."
fi

git push origin main
SHA=$(git rev-parse HEAD)
RUN_ID=""
for i in $(seq 1 30); do
  RUN_ID=$(gh run list -R Elusivedamir/svo --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')
  if [ -n "$RUN_ID" ]; then break; fi
  sleep 3
done
if [ -z "$RUN_ID" ]; then
  echo "Новая сборка ещё не зарегистрирована. Проверь: https://github.com/Elusivedamir/svo/actions" >&2
  exit 1
fi

echo "Проверяем APK: https://github.com/Elusivedamir/svo/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R Elusivedamir/svo --exit-status

DEST="$HOME/storage/shared/Download/SVO/v0.2.1"
mkdir -p "$DEST"
rm -f "$DEST/SVO-v0.2.1-debug.apk"
for i in $(seq 1 12); do
  if gh run download "$RUN_ID" -R Elusivedamir/svo --name SVO-v0.2.1-debug --dir "$DEST"; then
    break
  fi
  echo "Ожидаем публикацию APK ($i/12)..."
  sleep 5
done
APK="$DEST/SVO-v0.2.1-debug.apk"
if ! test -s "$APK"; then
  echo "APK ещё не доступен. Посмотри страницу сборки." >&2
  exit 1
fi
ls -lh "$APK"
echo "Готово: Мои файлы → Внутренняя память → Download → SVO → v0.2.1"
echo "Подтверди установку файла в Android (автоматическая установка ограничена системой)."
