#!/usr/bin/env bash
# Godot 편집기(Linux)와 내보내기 템플릿을 공식 릴리스에서 받아 SHA-512 를 확인한 뒤 푼다(GitHub Actions test·export 잡).
#   tools/fetch_godot.sh editor <폴더>                    → <폴더>/godot (실행 권한)
#   tools/fetch_godot.sh templates <템플릿폴더> <파일...>  → .tpz 의 templates/<파일> 들을 <템플릿폴더> 에
# 환경: GODOT_VERSION(예 4.4.1), GODOT_SHA512_SUMS(그 릴리스 SHA512-SUMS.txt 파일의 SHA-512 — 워크플로에 박아 둠),
#       GODOT_DOWNLOAD_BASE(없으면 https://github.com/godotengine/godot/releases/download/<판>-stable — 검사가 가짜 릴리스로 바꿈)
# 확인 순서: 공식 SHA512-SUMS.txt 를 같이 받아 박아 둔 값과 대조 → 받은 파일을 그 목록의 자기 줄과 대조.
# 하나라도 다르거나 받기가 실패하면(HTTP 오류 포함, curl -f) 풀기 전에 종료 코드 1 로 멈춘다.
set -euo pipefail

die() { echo "fetch_godot: $*" >&2; exit 1; }

[ $# -ge 2 ] || die "사용법: tools/fetch_godot.sh editor <폴더> | templates <템플릿폴더> <파일...>"
kind="$1"; dest="$2"; shift 2
: "${GODOT_VERSION:?GODOT_VERSION 이 필요합니다}"
: "${GODOT_SHA512_SUMS:?GODOT_SHA512_SUMS(SHA512-SUMS.txt 의 SHA-512)가 필요합니다}"
base="${GODOT_DOWNLOAD_BASE:-https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable}"
case "$kind" in
  editor) name="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" ;;
  templates) name="Godot_v${GODOT_VERSION}-stable_export_templates.tpz"; [ $# -ge 1 ] || die "풀 템플릿 파일 이름이 없습니다" ;;
  *) die "알 수 없는 종류: $kind (editor 또는 templates)" ;;
esac

tmp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/fetch_godot.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fetch() { curl -fsSL --retry 3 -o "$tmp/$1" "$base/$1" || die "받기 실패: $base/$1"; }

fetch SHA512-SUMS.txt
echo "${GODOT_SHA512_SUMS}  $tmp/SHA512-SUMS.txt" | sha512sum -c --quiet - \
  || die "SHA512-SUMS.txt 의 SHA-512 가 박아 둔 값과 다릅니다"
want="$(awk -v n="$name" '$2 == n { print $1 }' "$tmp/SHA512-SUMS.txt")"
[ "$(printf '%s\n' "$want" | grep -c .)" -eq 1 ] || die "SHA512-SUMS.txt 에 $name 줄이 하나가 아닙니다"
fetch "$name"
(cd "$tmp" && echo "$want  $name" | sha512sum -c --quiet -) || die "$name 의 SHA-512 가 SHA512-SUMS.txt 와 다릅니다"
echo "SHA-512 확인: $name"

mkdir -p "$dest"
if [ "$kind" = editor ]; then
  unzip -q "$tmp/$name" -d "$tmp/x"
  mv "$tmp/x/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$dest/godot"
  chmod +x "$dest/godot"
else
  files=()
  for f in "$@"; do files+=("templates/$f"); done
  unzip -q -o -j "$tmp/$name" "${files[@]}" -d "$dest"
fi
