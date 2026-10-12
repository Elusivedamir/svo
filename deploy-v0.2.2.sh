#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/svo"
REPO="Elusivedamir/svo"
ARTIFACT="SVO-v0.2.2-debug"
DEST="$HOME/storage/shared/Download/SVO/v0.2.2"

for binary in git gh; do
  command -v "$binary" >/dev/null 2>&1 || { echo "Не установлен $binary" >&2; exit 1; }
done

git add scripts/main_menu.gd scripts/menu_atmosphere.gd scripts/music_manager.gd \
  assets/audio/frontline_evening_theme.ogg export_presets.cfg \
  .github/workflows/android-apk.yml README_v0.2.2.txt deploy-v0.2.2.sh
if ! git diff --cached --quiet; then
  git commit -m "v0.2.2: audible soundtrack and large graphics controls"
else
  echo "Изменения уже включены в текущий коммит — повторный коммит не нужен."
fi

git push origin main
SHA="$(git rev-parse HEAD)"
RUN=""
echo "Ожидание сборки для коммита $SHA..."
for attempt in $(seq 1 45); do
  RUN="$(gh run list -R "$REPO" --commit "$SHA" --workflow android-apk.yml --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  [ -n "$RUN" ] && break
  sleep 4
done
[ -n "$RUN" ] || { echo "GitHub Actions пока не запустился. Посмотри https://github.com/$REPO/actions" >&2; exit 1; }
echo "Сборка: https://github.com/$REPO/actions/runs/$RUN"
gh run watch "$RUN" -R "$REPO" --exit-status
mkdir -p "$DEST"
rm -f "$DEST/$ARTIFACT.apk"
for attempt in $(seq 1 20); do
  if gh run download "$RUN" -R "$REPO" --name "$ARTIFACT" --dir "$DEST"; then
    if test -s "$DEST/$ARTIFACT.apk"; then
      echo "APK СКАЧАН:"
      ls -lh "$DEST/$ARTIFACT.apk"
      echo "Мои файлы → Внутренняя память → Download → SVO → v0.2.2"
      echo "Открой APK, подтверди установку Android."
      exit 0
    fi
  fi
  echo "APK ещё не доступен, повтор $attempt / 20"
  sleep 5
done
echo "Сборка прошла, но APK недоступен. Проверь страницу GitHub Actions." >&2
exit 1
