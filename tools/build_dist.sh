#!/usr/bin/env bash
# 배포판 만들기: Linux·Windows·웹 내보내기 → Godot 엔진 라이선스 고지 만들기 → 고지 파일 넣기 → zip 묶기.
# GitHub Actions(export 잡)와 로컬이 같은 절차를 쓴다.
#   GODOT=godot tools/build_dist.sh [결과폴더=build]
# 결과: <결과폴더>/linux·windows·web — 실행 파일(웹 묶음)과 고지 파일 넷(LICENSE·CREDITS.md·OFL-NanumGothic.txt·
#       GODOT-LICENSE.txt), <결과폴더>/slime-lab-<판>-linux.zip·-windows.zip, 내보내기 기록 <결과폴더>/logs/.
# 판은 project.godot 의 config/version 하나에서 읽는다. 태그 실행(GITHUB_REF_TYPE=tag)이면 태그가 v<판> 이어야 한다.
# GitHub Actions 안이면 판을 GITHUB_ENV 의 SLIME_LAB_VERSION 으로 넘긴다(산출물 이름).
# 실패(종료 코드 1): 판·태그 불일치, 내보내기 종료 코드, 기록의 WARNING·ERROR 줄, 실행 파일에 pck 가 묶이지 않음(끝 4바이트
# GDPC), Windows 실행 파일 정보가 프리셋 값이 아님, 고지 파일이 빠진 zip.
# Windows 실행 파일의 회사·제품·설명·저작권·판과 아이콘(프리셋 application/modify_resources=true)은 편집기 설정의 rcedit
# (Linux 에서는 wine 도)로 바꾼다(.github/workflows/build.yml 참고). 설정이 없으면 엔진이 WARNING 을 내고, rcedit 가 wine 안에서
# 죽으면(예: TMPDIR 이 아주 긴 경로) 엔진은 경고 없이 'Godot Engine' 그대로 두므로, 내보낸 파일에 프리셋 값(UTF-16)이 있는지 본다.
set -euo pipefail

die() { echo "build_dist: $*" >&2; exit 1; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot="${GODOT:-godot}"
mkdir -p "${1:-$root/build}"
out="$(cd "${1:-$root/build}" && pwd)"
notices=("$root/LICENSE" "$root/CREDITS.md" "$root/assets/fonts/OFL-NanumGothic.txt" "$out/GODOT-LICENSE.txt")

version="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$root/project.godot")"
[[ "$version" =~ ^[0-9A-Za-z._-]+$ ]] || die "project.godot 의 config/version 을 읽지 못했습니다: '$version'"
if [ "${GITHUB_REF_TYPE:-}" = tag ] && [ "${GITHUB_REF_NAME:-}" != "v$version" ]; then
  die "태그 ${GITHUB_REF_NAME:-} 가 project.godot 판 v$version 과 다릅니다"
fi
echo "판: $version"
if [ -n "${GITHUB_ENV:-}" ]; then echo "SLIME_LAB_VERSION=$version" >> "$GITHUB_ENV"; fi

# 프로젝트 안 build/ 에 내보내도 편집기가 웹 PNG 를 가져오지 않게(.import 파일·uid 항목이 남지 않게)
case "$out/" in "$root"/*) touch "$out/.gdignore" ;; esac
# 지난 내보내기에서 남은 파일(예전에 생긴 .import 등)이 묶음에 섞이지 않게 판마다 새 폴더
rm -rf -- "$out/linux" "$out/windows" "$out/web"
mkdir -p "$out/linux" "$out/windows" "$out/web" "$out/logs"

# 프리셋 이름, 출력 파일, 기록 이름
export_one() {
  local log="$out/logs/export-$3.log"
  "$godot" --headless --path "$root" --export-release "$1" "$2" > "$log" 2>&1 \
    || { tail -n 20 "$log"; die "내보내기 실패($1, 기록 $log)"; }
  if grep -nE "^(USER |SCRIPT )?(WARNING|ERROR):" "$log"; then die "내보내기 기록에 경고·오류($1, 기록 $log)"; fi
  [ -s "$2" ] || die "내보낸 파일이 없습니다: $2"
  echo "내보내기: $1 → $2"
}
# 실행 파일 끝에 pck 가 묶였는지(embed_pck 의 꼬리 표식)
has_pck() { [ "$(tail -c 4 "$1")" = GDPC ] || die "실행 파일에 pck 가 묶이지 않았습니다: $1"; }
# export_presets.cfg 의 "Windows Desktop" 프리셋 옵션 값(따옴표 벗김)
win_opt() {
  awk -v key="$1" '
    /^\[preset\.[0-9]+\]$/ { inopt = 0; next }
    /^\[preset\.[0-9]+\.options\]$/ { inopt = win; next }
    /^name="/ { win = ($0 == "name=\"Windows Desktop\"") }
    inopt && index($0, key "=") == 1 { v = substr($0, length(key) + 2); gsub(/^"|"$/, "", v); print v; exit }
  ' "$root/export_presets.cfg"
}
# 실행 파일 안에 글자들이 UTF-16LE(Windows 버전 정보가 쓰는 부호화)로 있는지. 없는 것을 찍고 실패.
has_utf16() {
  python3 -I -c 'import sys
d = open(sys.argv[1], "rb").read()
miss = [s for s in sys.argv[2:] if s.encode("utf-16le") not in d]
for s in miss:
    print("  없음: " + s)
sys.exit(1 if miss else 0)' "$@"
}

export_one "Linux" "$out/linux/slime-lab.x86_64" linux
export_one "Windows Desktop" "$out/windows/slime-lab.exe" windows
export_one "Web" "$out/web/index.html" web
has_pck "$out/linux/slime-lab.x86_64"
has_pck "$out/windows/slime-lab.exe"
if [ "$(win_opt application/modify_resources)" = true ]; then
  want=()
  for k in company_name product_name file_description copyright; do
    v="$(win_opt "application/$k")"
    if [ -n "$v" ]; then want+=("$v"); fi
  done
  if [[ "$version" =~ ^[0-9.]+$ ]]; then want+=("$version"); fi
  has_utf16 "$out/windows/slime-lab.exe" "${want[@]}" \
    || die "Windows 실행 파일 정보가 프리셋 값으로 바뀌지 않았습니다(rcedit·wine, 기록 $out/logs/export-windows.log)"
  echo "Windows 실행 파일 정보: ${want[*]}"
fi
for f in index.html index.js index.wasm index.pck; do [ -s "$out/web/$f" ] || die "웹 묶음에 $f 가 없습니다"; done

# 엔진 라이선스 고지(FreeType 등 제3자 포함) — 실제 엔진에서 읽어 만든다
"$godot" --headless --path "$root" --script res://tools/godot_license.gd -- --out="$out/GODOT-LICENSE.txt" \
  > "$out/logs/godot-license.log" 2>&1 || { cat "$out/logs/godot-license.log"; die "GODOT-LICENSE.txt 를 만들지 못했습니다"; }
grep -q "Godot Engine contributors" "$out/GODOT-LICENSE.txt" || die "GODOT-LICENSE.txt 에 엔진 저작권 문구가 없습니다"

for p in linux windows web; do cp "${notices[@]}" "$out/$p/"; done

for p in linux windows; do
  zip="$out/slime-lab-$version-$p.zip"
  rm -f "$zip"
  (cd "$out/$p" && zip -q -r "$zip" .)
  mapfile -t names < <(unzip -Z1 "$zip")
  for n in "${notices[@]}"; do
    [[ " ${names[*]} " == *" $(basename "$n") "* ]] || die "$(basename "$zip") 에 $(basename "$n") 이 없습니다"
  done
  echo "묶음: $zip"
  printf '  %s\n' "${names[@]}"
done
echo "웹 묶음: $out/web"
(cd "$out/web" && printf '  %s\n' *)
