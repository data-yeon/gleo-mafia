#!/bin/bash
# mk.sh 출력 입력... : 각 입력의 영상·소리를 맞춰 이어 붙인다(concat 필터)
out=$1; shift
args=(); fc=""; cat=""; n=0
for f in "$@"; do
  args+=(-i "$f")
  fc+="[${n}:v]fps=30,format=yuv420p,setsar=1[v${n}];[${n}:a]aresample=48000,aformat=channel_layouts=stereo[a${n}];"
  cat+="[v${n}][a${n}]"; n=$((n+1))
done
ffmpeg -v error -y "${args[@]}" -filter_complex "${fc}${cat}concat=n=${n}:v=1:a=1[v][ar];[ar]volume=-3dB,alimiter=limit=0.85[a]" \
  -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -c:a aac -b:a 160k -movflags +faststart "$out"
