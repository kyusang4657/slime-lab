#!/usr/bin/env bash
# 타임랩스 프레임(tests/timelapse_capture.gd 결과)을 mp4(H.264)와 gif 로 묶는다.
#   tools/make_timelapse.sh 프레임폴더 [결과폴더=docs/media]
set -euo pipefail
src="$1"; out="${2:-docs/media}"
mkdir -p "$out"
ffmpeg -y -loglevel error -framerate 30 -i "$src/f%05d.png" -c:v libx264 -pix_fmt yuv420p -crf 28 -preset slow \
  -movflags +faststart "$out/timelapse.mp4"
ffmpeg -y -loglevel error -framerate 30 -i "$src/f%05d.png" \
  -vf "fps=12,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
  "$out/timelapse.gif"
ffmpeg -y -loglevel error -i "$out/timelapse.mp4" -vf "select=eq(n\,$(( $(ls "$src" | wc -l) * 3 / 4 )))" -frames:v 1 -q:v 4 "$out/timelapse-poster.jpg"
ls -la "$out"
