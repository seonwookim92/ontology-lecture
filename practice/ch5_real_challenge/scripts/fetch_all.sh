#!/usr/bin/env bash
# =============================================================================
# fetch_all.sh — ch5 Real Challenge 전체 데이터 수집 진입점
#
# 실행:
#   bash scripts/fetch_all.sh            # 모든 소스 fetch (캐시 사용)
#   bash scripts/fetch_all.sh --force    # 모든 소스 강제 재다운로드
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$ROOT_DIR/data"
FORCE="${1:-}"

# ── 의존성 확인 ──────────────────────────────────────────────────────────────
for cmd in curl python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' 이(가) 필요합니다."
        exit 1
    fi
done

echo "=============================================="
echo "  CH5 Real Challenge — Data Fetch & Preprocess"
echo "=============================================="
echo "  출력 디렉토리: $DATA_DIR"
echo ""

mkdir -p "$DATA_DIR"/{mitre,kev,urlhaus,incidents}

# ── 각 소스 순서대로 실행 ─────────────────────────────────────────────────────
bash "$SCRIPT_DIR/fetch_mitre.sh"     "$DATA_DIR" $FORCE
echo ""
bash "$SCRIPT_DIR/fetch_kev.sh"       "$DATA_DIR" $FORCE
echo ""
bash "$SCRIPT_DIR/fetch_urlhaus.sh"   "$DATA_DIR" $FORCE
echo ""
bash "$SCRIPT_DIR/fetch_incidents.sh" "$DATA_DIR" $FORCE
echo ""

# ── 최종 결과 출력 ───────────────────────────────────────────────────────────
echo "=============================================="
echo "  완료! 생성된 파일 목록"
echo "=============================================="
find "$DATA_DIR" -name "*.json" ! -name "_raw*" | sort | while IFS= read -r f; do
    count=$(python3 -c "
import json, sys
try:
    d = json.load(open('$f'))
    print(len(d) if isinstance(d, list) else 1)
except Exception as e:
    print('?')
" 2>/dev/null)
    size=$(du -sh "$f" 2>/dev/null | cut -f1)
    rel="${f#$ROOT_DIR/}"
    printf "  [%6s records | %4s]  %s\n" "$count" "$size" "$rel"
done
echo ""
