#!/bin/zsh
# 시연 영상 녹화: Godot Movie Maker(고정 30fps, 1920x1080)로 클립 3개(튜토리얼 / 본 사건 / 놓친 결말)를 녹화하고
# 제목 카드를 붙여 video/1_tutorial.mp4, 2_main_case.mp4, 3_missed_ending.mp4로 만든다.
# 실행: tools/video/record_demo.sh  (Godot 창이 맨 위에 뜬다. 녹화 중에는 가리거나 최소화하지 말 것. 약 8분)
set -e
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SP=$REPO/video/.work
mkdir -p $SP
cd $REPO
printf '[display]\n\nwindow/size/window_width_override=1920\nwindow/size/window_height_override=1080\n' > godot/override.cfg
trap 'rm -f $REPO/godot/override.cfg' EXIT

TUT="w3,until=offer,w3,click=card,w5,click=card,w5.5,click=card,w3,click=pin4,w1.5,click=go,waitfx,w4.5,click=coach,w2,click=pin1,w1.2,click=go,waitfx,w1.5,click=pin2,w1.2,click=go,waitfx,w6,click=coach,until=stakeopen5,w2.5,click=pin5,w1.2,click=opt:stakeout,w1,click=go,until=heard5,w4,click=chip1,w3.5,click=pin1,w1.2,click=raid,w1,click=raid,w12,w6"
MAIN="w3,until=offer,w4,click=card,w6,click=card,w6.5,click=card,w6,click=card,w2,click=pin2,w1.2,click=go,waitfx,w3,click=pin6,w1.2,click=go,waitfx,w3,rush=stake,w1.5,click=alert,w2,rush=heard1,w5,rush=tunnel,click=pin9,w1,click=go,waitfx,w6,click=chip6,w5,click=pin7,w1.2,click=raid,w1,click=raid,w8,click=pin8,w1.2,click=raid,w1,click=raid,w12,w8"
MISS="w3,until=offer,w2,click=card,w2.5,click=card,w2.5,click=card,w2.5,click=card,w2,click=pin6,w1.2,click=go,waitfx,w2.5,click=pin8,w1.2,click=go,waitfx,w3.5,click=pin9,w1.2,click=raid,w1,click=raid,w7,rush=final@40,w5,rush=arrive@15,w13,w6"

rec() {   # rec 이름 "인자들" "대본"
  rm -f $SP/$1.avi
  # 화면이 꺼지거나 가려지면 Godot이 그리기를 멈추고 같은 장면만 저장한다 → 잠자기 막기 + 항상 위
  caffeinate -dimsu godot --path godot --always-on-top --write-movie $SP/$1.avi --fixed-fps 30 -- ${=2} --autoplay="$3" --screenshot=$SP/$1_end.png 2>&1 \
    | grep -E "frames at|ERROR|SCRIPT|click:" || true
}
echo "== 1 튜토리얼"; rec clip1 "--tutorial" "$TUT"
echo "== 2 본 사건"; rec clip2 "--mode=demo" "$MAIN"
echo "== 3 놓친 결말"; rec clip3 "--mode=demo" "$MISS"
rm -f godot/override.cfg

# 제목 카드
~/.pyenv/shims/python3 - $SP <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFont
sp = sys.argv[1]
big = ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc', 84, index=6)
mid = ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc', 40, index=0)
small = ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc', 30, index=0)
cards = {
 "t0": ("수사망 (Gleo Mafia)", "자율주행 출근길, Pleos 차량 화면 위에서 푸는 추리 게임", "Hyundai Pleos · Gleo AI 해커톤 데모"),
 "t1": ("1. 수습 첫날", "처음 하는 사람을 위한 튜토리얼 · 장소 6곳, 숨은 놈 1명", "회신 전화 → 경우의 수 → 같은 직업 두 명 → 현장 확인 → 출동"),
 "t2": ("2. 보이스피싱 인출책 추적", "본부 긴급 첩보 · 제보 9통 중 2통은 놈들이 건 가짜", "회신 전화 · 현장 확인 · 말이 안 맞음 · 수사망 · 출동 · 검거"),
 "t3": ("3. 놓친 결말", "가짜 경관과 취객의 말에 속으면", "헛걸음 · 최종 단계 · 인출 완료 · 어디서 속았나 되짚기"),
}
for k, (a, b, c) in cards.items():
    im = Image.new('RGB', (1920, 1080), (238, 241, 245))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((260, 330, 1660, 750), 36, fill=(255, 255, 255))
    d.rectangle((260, 330, 276, 750), fill=(47, 107, 255))
    d.text((330, 390), a, font=big, fill=(26, 32, 44))
    d.text((334, 530), b, font=mid, fill=(74, 84, 102))
    d.text((334, 620), c, font=small, fill=(47, 107, 255))
    im.save(f'{sp}/{k}.png')
PY

# 각 조각을 같은 규격(1920x1080 30fps, 48kHz 스테레오)의 mp4로 만들고 이어 붙인다
enc() { ffmpeg -v error -y "$@" -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -r 30 -c:a aac -b:a 160k -ar 48000 -ac 2; }
for t in t0 t1 t2 t3; do
  dur=3.5; [ $t = t0 ] && dur=4.5
  enc -loop 1 -t $dur -i $SP/$t.png -f lavfi -t $dur -i anullsrc=r=48000:cl=stereo -shortest $SP/$t.mp4
done
for c in clip1 clip2 clip3; do enc -i $SP/$c.avi $SP/$c.mp4 && rm -f $SP/$c.avi; done
# 멈춘 구간(같은 화면 20초 이상) 검사
for c in clip1 clip2 clip3; do
  echo "freeze $c:"; ffmpeg -i $SP/$c.mp4 -vf freezedetect=n=0.0005:d=20 -map 0:v -f null - 2>&1 | grep -E "freeze_(start|duration)" | tr '\n' ' '; echo
  ffprobe -v error -show_entries format=duration -of csv=p=0 $SP/$c.mp4
done
MK=$REPO/tools/video/join.sh
$MK $REPO/video/1_tutorial.mp4 $SP/t0.mp4 $SP/t1.mp4 $SP/clip1.mp4
$MK $REPO/video/2_main_case.mp4 $SP/t2.mp4 $SP/clip2.mp4
$MK $REPO/video/3_missed_ending.mp4 $SP/t3.mp4 $SP/clip3.mp4
rm -rf $SP
for f in $REPO/video/*.mp4; do echo "$(basename $f) $(ffprobe -v error -show_entries format=duration -of csv=p=0 $f)초"; done
