#!/usr/bin/env bash
# =============================================================================
# fetch_kev.sh — CISA Known Exploited Vulnerabilities 다운로드 및 전처리
#
# 출처 : https://www.cisa.gov/known-exploited-vulnerabilities-catalog
#
# 출력 (data/kev/):
#   vulnerabilities.json  — ~1,500개 실제 악용된 취약점 목록 (CVE 기준)
# =============================================================================
set -euo pipefail

DATA_DIR="${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data}"
OUT_DIR="$DATA_DIR/kev"
RAW_FILE="$OUT_DIR/_raw_kev.json"
FORCE="${2:-}"
KEV_URL="https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"

mkdir -p "$OUT_DIR"

# ── 다운로드 ──────────────────────────────────────────────────────────────────
if [[ ! -f "$RAW_FILE" ]] || [[ "$FORCE" == "--force" ]]; then
    echo "[KEV] CISA KEV 카탈로그 다운로드 중..."
    curl -fSL --progress-bar "$KEV_URL" -o "$RAW_FILE"
    echo "[KEV] 다운로드 완료: $(du -sh "$RAW_FILE" | cut -f1)"
else
    echo "[KEV] 캐시된 파일 사용: $(du -sh "$RAW_FILE" | cut -f1)"
fi

echo "[KEV] 취약점 데이터 정규화 중..."

export KEV_OUT_DIR="$OUT_DIR"
export KEV_RAW_FILE="$RAW_FILE"

python3 << 'PYEOF'
import json, os

out_dir  = os.environ['KEV_OUT_DIR']
raw_path = os.environ['KEV_RAW_FILE']

with open(raw_path, encoding='utf-8') as f:
    raw = json.load(f)

# KEV JSON 구조: { "vulnerabilities": [...], "count": N, ... }
raw_list = raw.get('vulnerabilities', [])
print(f"  원본 레코드 수: {len(raw_list):,}")

# ── 필드 정규화 ───────────────────────────────────────────────────────────────
# CISA 원본 필드명 → 우리 스키마 필드명 매핑
vulnerabilities = []
for row in raw_list:
    cve_id = (row.get('cveID') or '').strip()
    if not cve_id:
        continue

    vulnerabilities.append({
        'cve_id':          cve_id,                                    # 고유 키 (KEV ↔ Incidents 교차 연결)
        'name':            (row.get('vulnerabilityName') or '').strip(),
        'vendor':          (row.get('vendorProject') or '').strip(),
        'product':         (row.get('product') or '').strip(),
        'description':     (row.get('shortDescription') or '').strip()[:1000],
        'date_added':      (row.get('dateAdded') or '').strip(),
        'required_action': (row.get('requiredAction') or '').strip()[:500],
        'due_date':        (row.get('dueDate') or '').strip(),
        # "Known" | "Unknown" — 랜섬웨어 캠페인 악용 여부
        'ransomware_use':  (row.get('knownRansomwareCampaignUse') or 'Unknown').strip(),
        'notes':           (row.get('notes') or '').strip()[:300],
    })

# ── 출력 ──────────────────────────────────────────────────────────────────────
out_path = os.path.join(out_dir, 'vulnerabilities.json')
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(vulnerabilities, f, ensure_ascii=False, indent=2)

print(f"  정규화 완료: {len(vulnerabilities):,} 개 취약점")
print(f"  출력: {out_path}")

# ── 통계 ──────────────────────────────────────────────────────────────────────
ransomware_count = sum(1 for v in vulnerabilities if v['ransomware_use'] == 'Known')
print(f"  - 랜섬웨어 연관 취약점: {ransomware_count:,} 개")
vendors = {}
for v in vulnerabilities:
    vendors[v['vendor']] = vendors.get(v['vendor'], 0) + 1
top5 = sorted(vendors.items(), key=lambda x: -x[1])[:5]
print(f"  - 상위 5개 벤더: {', '.join(f'{v}({c})' for v,c in top5)}")

PYEOF

echo "[KEV] 완료!"
