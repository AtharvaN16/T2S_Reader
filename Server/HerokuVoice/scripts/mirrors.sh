#!/usr/bin/env bash
# Deploys Server/HerokuVoice to N identical Heroku Eco apps and verifies each one.
# Safe to re-run: every step is idempotent. Eco only, by construction.
#
#   scripts/mirrors.sh [count]        default 4
#
# The bearer key is read from $T2S_VOICE_KEY_FILE (default ~/.t2s/heroku-voice-key),
# which must be mode 0600. It is never printed.
set -euo pipefail

COUNT="${1:-4}"
PRIMARY="kokoro-t2s"
KEY_FILE="${T2S_VOICE_KEY_FILE:-$HOME/.t2s/heroku-voice-key}"
SIZE="eco"                                    # the only size this script will ever scale to

case "$COUNT" in ''|*[!0-9]*) echo "count must be a positive integer" >&2; exit 2;; esac
[ "$COUNT" -ge 1 ] || { echo "count must be at least 1" >&2; exit 2; }
[ -f "$KEY_FILE" ] || { echo "no key file at $KEY_FILE" >&2; exit 2; }
[ "$(stat -f '%Lp' "$KEY_FILE")" = "600" ] || { echo "$KEY_FILE must be mode 0600" >&2; exit 2; }
KEY="$(<"$KEY_FILE")"
[ -n "$KEY" ] || { echo "key file is empty" >&2; exit 2; }

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"
if [ -n "$(git status --porcelain -- Server/HerokuVoice)" ]; then
  echo "commit Server/HerokuVoice first: mirrors deploy committed history" >&2
  exit 2
fi

apps=("$PRIMARY")
for i in $(seq 2 "$COUNT"); do apps+=("$PRIMARY-m$i"); done

echo "splitting Server/HerokuVoice from $(git rev-parse --short HEAD)"
SPLIT="$(git subtree split --prefix=Server/HerokuVoice HEAD)"

for app in "${apps[@]}"; do
  echo "== $app"
  if ! heroku apps:info -a "$app" >/dev/null 2>&1; then
    heroku apps:create "$app" --stack heroku-24 --region us >/dev/null
  fi
  heroku buildpacks -a "$app" 2>/dev/null | grep -q "heroku/python" || heroku buildpacks:set heroku/python -a "$app" >/dev/null
  heroku config:set T2S_VOICE_API_KEY="$KEY" MALLOC_ARENA_MAX=2 PYTHONUNBUFFERED=1 -a "$app" >/dev/null
  # Eco keeps one thread and no arena, the settings 512 MB survives; a tier test may have set these.
  heroku config:unset T2S_ORT_THREADS T2S_ORT_ARENA -a "$app" >/dev/null 2>&1 || true
  heroku labs:enable log-runtime-metrics -a "$app" >/dev/null 2>&1 || true
  if ! git push -f "https://git.heroku.com/$app.git" "$SPLIT:refs/heads/main" > "/tmp/mirrors-push-$app.log" 2>&1; then
    echo "push to $app failed:" >&2; tail -20 "/tmp/mirrors-push-$app.log" >&2; exit 1
  fi
  grep -E "Released v|deployed to Heroku|Everything up-to-date" "/tmp/mirrors-push-$app.log" || true
  heroku ps:scale "web=1:$SIZE" -a "$app" >/dev/null
done

echo "== verifying"
fail=0
for app in "${apps[@]}"; do
  url="$(heroku apps:info -a "$app" --json | python3 -c 'import sys, json; print(json.load(sys.stdin)["app"]["web_url"].rstrip("/"))')"
  for _ in $(seq 1 36); do
    curl -sf --max-time 10 "$url/health" >/dev/null 2>&1 && break
    sleep 5
  done
  health="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url/health")"
  ctype="$(curl -s -o /dev/null -w '%{content_type}' --max-time 90 -X POST "$url/v1/audio/speech" \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d '{"model":"kokoro","input":"Mirror check.","voice":"af_heart","response_format":"pcm"}')"
  dyno="$(heroku ps -a "$app" --json | python3 -c 'import sys, json; d = json.load(sys.stdin); print(d[0]["size"] if d else "none")')"
  addons="$(heroku addons -a "$app" --json | python3 -c 'import sys, json; print(len(json.load(sys.stdin)))')"
  printf '%-16s health=%s render=%s dyno=%s addons=%s  %s/v1/audio/speech\n' "$app" "$health" "$ctype" "$dyno" "$addons" "$url"
  [ "$health" = "200" ] && [ "$ctype" = "audio/pcm" ] && [ "$dyno" = "Eco" ] && [ "$addons" = "0" ] || fail=1
done
exit "$fail"
