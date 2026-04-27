#!/usr/bin/env bash
# =============================================================================
# fetch_incidents.sh — 가상 사건 데이터 다운로드 및 전처리
#
# 출처 : GitHub Gist (커스텀 생성 한국 사이버 보안 사건 60+ 건)
#
# 출력 (data/incidents/):
#   incidents.json  — 전처리된 사건 목록
#
# 사건 데이터 구조:
#   {
#     "incident_id": "incident--uuid",
#     "title": "한국수력원자력 원전제어망 침투 시도",
#     "timestamp": "2025-03-15T09:23:00Z",
#     "victim": { "organization", "system", "industry", "country" },
#     "attribution": { "group_name", "confidence" },
#     "summary": "...",
#     "attack_flow": [
#       {
#         "step": 1,
#         "phase": "Initial Access",
#         "technique": "T1190 - Exploit Public-Facing Application",
#         "description": "...",
#         "outcome": "Success",
#         "related_entity": { "type": "Vulnerability|Malware|Indicator|Technique", "value": "CVE-2025-14847" }
#       }
#     ]
#   }
#
# 교차 연결 포인트:
#   attribution.group_name        → ThreatActor.name (MITRE와 연결)
#   attack_flow[].technique       → Technique (T-코드 파싱)
#   attack_flow[].related_entity  → Vulnerability/Malware/Indicator (타입별 연결)
# =============================================================================
set -euo pipefail

DATA_DIR="${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data}"
OUT_DIR="$DATA_DIR/incidents"
RAW_FILE="$OUT_DIR/_raw_incidents.json"
FORCE="${2:-}"
INCIDENTS_URL="https://gist.githubusercontent.com/seonwookim92/50c01163876100642d927ee895fbd5fc/raw/bd5482941cc35f95fe19a36bcc99caf629d4ffa8/incidents.json"

mkdir -p "$OUT_DIR"

# ── 다운로드 ──────────────────────────────────────────────────────────────────
if [[ ! -f "$RAW_FILE" ]] || [[ "$FORCE" == "--force" ]]; then
    echo "[Incidents] 사건 데이터 다운로드 중..."
    curl -fSL --progress-bar "$INCIDENTS_URL" -o "$RAW_FILE"
    echo "[Incidents] 다운로드 완료: $(du -sh "$RAW_FILE" | cut -f1)"
else
    echo "[Incidents] 캐시된 파일 사용: $(du -sh "$RAW_FILE" | cut -f1)"
fi

echo "[Incidents] 사건 데이터 전처리 중..."

export INCIDENTS_OUT_DIR="$OUT_DIR"
export INCIDENTS_RAW_FILE="$RAW_FILE"

python3 << 'PYEOF'
import json, os, re

out_dir  = os.environ['INCIDENTS_OUT_DIR']
raw_path = os.environ['INCIDENTS_RAW_FILE']

with open(raw_path, encoding='utf-8') as f:
    raw = json.load(f)

# 원본이 배열인지 dict 형태인지 확인
incidents_raw = raw if isinstance(raw, list) else raw.get('incidents', [raw])
print(f"  원본 사건 수: {len(incidents_raw)}")

# T-코드 추출 패턴 (예: "T1190", "T1059.001")
TECHNIQUE_ID_RE = re.compile(r'\b(T\d{4}(?:\.\d{3})?)\b')

# ── 전처리 ────────────────────────────────────────────────────────────────────
incidents = []
for raw_inc in incidents_raw:
    # attack_flow 각 단계에서 technique_id 추출
    attack_flow = []
    for step in raw_inc.get('attack_flow', []):
        tech_str = step.get('technique', '')
        # "T1190 - Exploit Public-Facing Application" 등에서 T-코드 파싱
        tech_ids = TECHNIQUE_ID_RE.findall(tech_str)
        technique_id = tech_ids[0] if tech_ids else None

        # technique 자연어 이름 (T-코드 이후 부분)
        technique_name = re.sub(r'^T\d{4}(?:\.\d{3})?\s*[-–]\s*', '', tech_str).strip()

        attack_flow.append({
            'step':           step.get('step'),
            'phase':          step.get('phase', '').strip(),
            'technique_id':   technique_id,    # T-코드 (MITRE Technique과 연결)
            'technique_name': technique_name,  # 자연어 이름
            'description':    step.get('description', '').strip(),
            'outcome':        step.get('outcome', '').strip(),
            # related_entity: { type: "Vulnerability|Malware|Indicator|Technique", value: "..." }
            'related_entity': step.get('related_entity'),
        })

    victim = raw_inc.get('victim', {})
    attribution = raw_inc.get('attribution', {})

    incidents.append({
        'incident_id':   raw_inc.get('id', '').strip(),
        'title':         raw_inc.get('title', '').strip(),
        'timestamp':     raw_inc.get('timestamp', '').strip(),
        'summary':       raw_inc.get('summary', '').strip()[:2000],
        # victim 정보 → Victim 노드 생성
        'org_name':      victim.get('organization', '').strip(),
        'system':        victim.get('system', '').strip(),
        'industry':      victim.get('industry', '').strip(),
        'country':       victim.get('country', '').strip(),
        # 귀속 정보 → ThreatActor 노드와 연결 (MITRE group_name 기준)
        'threat_actor':  attribution.get('group_name', '').strip(),
        'confidence':    attribution.get('confidence', '').strip(),
        # 전처리된 공격 흐름
        'attack_flow':   attack_flow,
    })

# ── 출력 ──────────────────────────────────────────────────────────────────────
out_path = os.path.join(out_dir, 'incidents.json')
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(incidents, f, ensure_ascii=False, indent=2)

print(f"  처리 완료: {len(incidents):,} 개 사건")
print(f"  출력: {out_path}")

# ── 통계 ──────────────────────────────────────────────────────────────────────
industries = {}
actors = {}
outcomes = {'Success': 0, 'Blocked': 0, 'Detected': 0}
entity_types = {}
total_steps = 0

for inc in incidents:
    industries[inc['industry']] = industries.get(inc['industry'], 0) + 1
    actors[inc['threat_actor']] = actors.get(inc['threat_actor'], 0) + 1
    for step in inc['attack_flow']:
        total_steps += 1
        oc = step.get('outcome', '')
        if oc in outcomes:
            outcomes[oc] += 1
        re_item = step.get('related_entity') or {}
        et = re_item.get('type', '')
        if et:
            entity_types[et] = entity_types.get(et, 0) + 1

top_industries = sorted(industries.items(), key=lambda x: -x[1])[:4]
top_actors = sorted(actors.items(), key=lambda x: -x[1])[:3]

print(f"  - 총 공격 단계: {total_steps:,}")
print(f"  - 공격 결과: Success={outcomes['Success']}, Blocked={outcomes['Blocked']}, Detected={outcomes['Detected']}")
print(f"  - 관련 엔티티 타입: {entity_types}")
print(f"  - 주요 피해 산업: {', '.join(f'{k}({v})' for k,v in top_industries)}")
print(f"  - 주요 위협 행위자: {', '.join(f'{k}({v})' for k,v in top_actors)}")

PYEOF

echo "[Incidents] 완료!"
