#!/usr/bin/env bash
# 내보낸 Linux 실행 파일을 빈 폴더에서 헤드리스로 잠깐 띄워 본다(GitHub Actions export 잡).
#   tools/smoke_run.sh <실행 파일> [프레임=200]
# 실패(종료 코드 1): 실행 파일 끝에 pck 표식(GDPC)이 없음, 실행 파일 종료 코드가 0 이 아님(충돌 포함), 메인 장면
# (project.godot 의 run/main_scene)을 읽은 줄이 없음, 기록에 ERROR·WARNING·SCRIPT ERROR 줄이나 "Couldn't load project data".
# 빈 폴더에서 띄우는 까닭: 저장소 뿌리에서 띄우면 pck 가 없어도 엔진이 그 자리의 project.godot·소스로 대신 떠서 통과한다.
set -euo pipefail

die() { echo "smoke_run: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "사용법: tools/smoke_run.sh <실행 파일> [프레임=200]"
exe="$1"; frames="${2:-200}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -s "$exe" ] || die "실행 파일이 없습니다: $exe"
[ "$(tail -c 4 "$exe")" = GDPC ] || die "실행 파일에 pck 가 묶이지 않았습니다: $exe"
scene="$(sed -n 's/^run\/main_scene="res:\/\/\(.*\)\.tscn"$/\1/p' "$root/project.godot")"
[ -n "$scene" ] || die "project.godot 에서 run/main_scene 을 읽지 못했습니다"
scene="${scene##*/}"

dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/smoke_run.XXXXXX")"
trap 'rm -rf "$dir"' EXIT
cp "$exe" "$dir/"
log="$dir/run.log"
rc=0
(cd "$dir" && "./$(basename "$exe")" --headless --verbose --quit-after "$frames") > "$log" 2>&1 || rc=$?
grep -v -e ALSA -e "^Loading resource:" "$log" | tail -n 8 || true
[ "$rc" -eq 0 ] || die "실행 파일 종료 코드 $rc"
# 내보낸 장면은 res://.godot/exported/…-<이름>.scn 으로 바뀌어 읽힌다
grep -qE "^Loading resource: res://.*[/-]${scene}\.t?scn$" "$log" || die "메인 장면($scene)을 읽은 기록이 없습니다"
if grep -nE "^(USER |SCRIPT )?(WARNING|ERROR):|Couldn't load project data" "$log"; then die "실행 기록에 경고·오류"; fi
echo "실행 확인: $(basename "$exe") ${frames}프레임, 메인 장면 $scene, 종료 코드 0"
