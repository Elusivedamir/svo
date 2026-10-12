#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/svo"

if ! command -v gh >/dev/null 2>&1; then
    echo "Ошибка: установи gh: pkg install gh -y"
    exit 1
fi

# Stage only files supplied with this patch, leaving unrelated local work untouched.
git add project.godot export_presets.cfg scenes/main_menu.tscn scripts/main_menu.gd scripts/loading.gd \
  .github/workflows/android-apk.yml assets/icons/app_icon.png assets/icons/launcher_192.png \
  assets/icons/adaptive_foreground_432.png assets/icons/adaptive_background_432.png deploy-v0.2.sh

if ! git diff --cached --quiet; then
    git commit -m "v0.2: main menu and approved app icon"
else
    echo "Изменения уже включены в коммит; проверим сборку текущей версии."
fi

git push origin main
SHA=$(git rev-parse HEAD)
echo "GitHub SHA: $SHA"

RUN_ID=""
for i in $(seq 1 30); do
    RUN_ID=$(gh run list -R Elusivedamir/svo --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')
    if [ -n "$RUN_ID" ]; then break; fi
    sleep 3
done
if [ -z "$RUN_ID" ]; then
    echo "Не удалось найти сборку. Открой https://github.com/Elusivedamir/svo/actions"
    exit 1
fi

echo "Ожидание GitHub Actions #$RUN_ID..."
gh run watch "$RUN_ID" -R Elusivedamir/svo --exit-status

DEST="$HOME/storage/shared/Download/SVO/v0.2"
mkdir -p "$DEST"
rm -f "$DEST/SVO-v0.2-debug.apk"

# GitHub can take a few seconds to publish the artifact after the job completes.
DOWNLOADED=0
for i in $(seq 1 10); do
    if gh run download "$RUN_ID" -R Elusivedamir/svo --name SVO-v0.2-debug --dir "$DEST"; then
        DOWNLOADED=1
        break
    fi
    echo "Файл ещё публикуется, попытка $i/10..."
    sleep 5
done
if [ "$DOWNLOADED" -ne 1 ]; then
    echo "APK пока недоступен. Проверь https://github.com/Elusivedamir/svo/actions/runs/$RUN_ID"
    exit 1
fi

APK="$DEST/SVO-v0.2-debug.apk"
test -s "$APK"
echo "APK готов: $APK"
ls -lh "$APK"
echo "Открой: Мои файлы → Внутренняя память → Download → SVO → v0.2"
# OS confirmation is required; opening an APK automatically is not reliable on Samsung.
