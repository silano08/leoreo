#!/usr/bin/env bash
# leoreo 설치 스크립트
# 저장소를 ~/.leoreo에 받아서 Claude Code 스킬 7개를 심링크로 설치합니다.
# leoreo, leoreo-metrics, leoreo-model, leoreo-pay, leoreo-retain, leoreo-cost, leoreo-b2b
set -euo pipefail

REPO_URL="https://github.com/animepics/leoreo.git"
REPO_DIR="${LEOREO_DIR:-$HOME/.leoreo}"
SKILLS_DIR="$HOME/.claude/skills"

if [ -d "$REPO_DIR/.git" ]; then
  echo "기존 설치를 업데이트합니다: $REPO_DIR"
  git -C "$REPO_DIR" pull --ff-only
else
  echo "저장소를 받습니다: $REPO_DIR"
  git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi

mkdir -p "$SKILLS_DIR"
ln -sfn "$REPO_DIR" "$SKILLS_DIR/leoreo"
ln -sfn "$REPO_DIR/leoreo-model" "$SKILLS_DIR/leoreo-model"
ln -sfn "$REPO_DIR/leoreo-pay" "$SKILLS_DIR/leoreo-pay"
ln -sfn "$REPO_DIR/leoreo-metrics" "$SKILLS_DIR/leoreo-metrics"
ln -sfn "$REPO_DIR/leoreo-cost" "$SKILLS_DIR/leoreo-cost"
ln -sfn "$REPO_DIR/leoreo-retain" "$SKILLS_DIR/leoreo-retain"
ln -sfn "$REPO_DIR/leoreo-b2b" "$SKILLS_DIR/leoreo-b2b"

echo ""
echo "설치 완료. Claude Code에서 바로 쓸 수 있습니다."
echo "  /leoreo         돈 버는 개발 진단"
echo "  /leoreo-metrics 계측·실험 설계"
echo "  /leoreo-model   수익모델·가격 설계"
echo "  /leoreo-pay     한국 결제시스템"
echo "  /leoreo-retain  유지·확장"
echo "  /leoreo-cost    원가·마진"
echo "  /leoreo-b2b     엔터프라이즈 게이트"
