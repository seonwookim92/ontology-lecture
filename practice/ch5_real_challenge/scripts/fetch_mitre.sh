#!/usr/bin/env bash
# =============================================================================
# fetch_mitre.sh — MITRE ATT&CK 다운로드 및 전처리
#
# 출처 : https://github.com/mitre/cti (STIX 2.1 Bundle, ~43MB)
#
# 출력 (data/mitre/):
#   tactics.json        — 14개 전술 (TA-코드)
#   techniques.json     — ~700개 기법 (T-코드)
#   threat_actors.json  — ~150개 위협 행위자 (APT 그룹)
#   malware.json        — ~700개 악성코드 패밀리
#   tools.json          — ~80개 해킹 도구
#   mitigations.json    — ~200개 완화 조치
#   relationships.json  — 전체 관계 (Neo4j 라벨 사전 매핑 완료)
# =============================================================================
set -euo pipefail

DATA_DIR="${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data}"
OUT_DIR="$DATA_DIR/mitre"
RAW_FILE="$OUT_DIR/_raw_bundle.json"
FORCE="${2:-}"
MITRE_URL="https://raw.githubusercontent.com/mitre/cti/master/enterprise-attack/enterprise-attack.json"

mkdir -p "$OUT_DIR"

# ── 다운로드 (캐시 없거나 --force 시) ─────────────────────────────────────────
if [[ ! -f "$RAW_FILE" ]] || [[ "$FORCE" == "--force" ]]; then
    echo "[MITRE] ATT&CK 번들 다운로드 중... (~43MB, 잠시 기다려 주세요)"
    curl -fSL --progress-bar "$MITRE_URL" -o "$RAW_FILE"
    echo "[MITRE] 다운로드 완료: $(du -sh "$RAW_FILE" | cut -f1)"
else
    echo "[MITRE] 캐시된 번들 사용: $(du -sh "$RAW_FILE" | cut -f1)"
fi

echo "[MITRE] STIX 객체 파싱 및 분류 중..."

# ── Python 전처리 ─────────────────────────────────────────────────────────────
export MITRE_OUT_DIR="$OUT_DIR"
export MITRE_RAW_FILE="$RAW_FILE"

python3 << 'PYEOF'
import json, os, sys

out_dir  = os.environ['MITRE_OUT_DIR']
raw_path = os.environ['MITRE_RAW_FILE']

print(f"  파일 로딩: {raw_path}")
with open(raw_path, encoding='utf-8') as f:
    bundle = json.load(f)

objects = bundle.get('objects', [])
print(f"  STIX 객체 수: {len(objects):,}")

# ── 헬퍼 함수 ─────────────────────────────────────────────────────────────────

def get_mitre_id(obj):
    """MITRE ATT&CK 외부 참조에서 T/TA/M-코드 추출"""
    for ref in obj.get('external_references', []):
        if ref.get('source_name') == 'mitre-attack':
            return ref.get('external_id', '')
    return ''

def truncate(s, n=1000):
    s = s or ''
    return s[:n]

def is_valid(obj):
    """deprecated 혹은 revoked 객체 제외"""
    return (
        not obj.get('revoked', False) and
        not obj.get('x_mitre_deprecated', False)
    )

# ── 전체 객체 ID 맵 (관계 해석용) ─────────────────────────────────────────────
id_map = {obj['id']: obj for obj in objects if 'id' in obj}

# ── 결과 컨테이너 ─────────────────────────────────────────────────────────────
tactics        = []
techniques     = []
threat_actors  = []
malware_list   = []
tools          = []
mitigations    = []
relationships  = []

# 전술 shortname → stix_id (기법-전술 연결용)
tactic_stix_by_shortname = {}

# =============================================================================
# Pass 1: 노드 타입별 추출
# =============================================================================
print("  [1/3] 노드 추출 중...")

for obj in objects:
    t = obj.get('type', '')

    # ── Tactic (x-mitre-tactic) ───────────────────────────────────────────────
    if t == 'x-mitre-tactic':
        shortname = obj.get('x_mitre_shortname', '')
        tactic_stix_by_shortname[shortname] = obj['id']
        tactics.append({
            'stix_id':     obj['id'],
            'tactic_id':   get_mitre_id(obj),
            'name':        obj.get('name', ''),
            'shortname':   shortname,
            'description': truncate(obj.get('description', '')),
        })

    # ── Technique (attack-pattern) ────────────────────────────────────────────
    elif t == 'attack-pattern' and is_valid(obj):
        name = obj.get('name', '')
        # MITRE kill-chain 기준 phase 이름만 수집
        phases = [
            kcp['phase_name']
            for kcp in obj.get('kill_chain_phases', [])
            if kcp.get('kill_chain_name') == 'mitre-attack'
        ]
        raw_aliases = obj.get('x_mitre_aliases') or []
        techniques.append({
            'stix_id':         obj['id'],
            'technique_id':    get_mitre_id(obj),
            'name':            name,
            'description':     truncate(obj.get('description', '')),
            'is_subtechnique': obj.get('x_mitre_is_subtechnique', False),
            'platforms':       obj.get('x_mitre_platforms', []),
            'tactic_phases':   phases,
            'aliases':         [a for a in raw_aliases if a != name],
        })

    # ── ThreatActor (intrusion-set) ───────────────────────────────────────────
    elif t == 'intrusion-set' and is_valid(obj):
        name = obj.get('name', '')
        raw_aliases = obj.get('aliases') or []
        threat_actors.append({
            'stix_id':     obj['id'],
            'name':        name,
            'aliases':     [a for a in raw_aliases if a != name],
            'description': truncate(obj.get('description', '')),
        })

    # ── Malware (malware) ─────────────────────────────────────────────────────
    elif t == 'malware' and is_valid(obj):
        name  = obj.get('name', '')
        types = obj.get('malware_types') or []
        raw_aliases = obj.get('x_mitre_aliases') or []
        malware_list.append({
            'stix_id':      obj['id'],
            'name':         name,
            'malware_type': types[0] if types else 'unknown',
            'description':  truncate(obj.get('description', '')),
            'aliases':      [a for a in raw_aliases if a != name],
        })

    # ── Tool (tool) ───────────────────────────────────────────────────────────
    elif t == 'tool' and is_valid(obj):
        types = obj.get('tool_types') or []
        tools.append({
            'stix_id':     obj['id'],
            'name':        obj.get('name', ''),
            'tool_type':   types[0] if types else 'unknown',
            'description': truncate(obj.get('description', '')),
        })

    # ── Mitigation (course-of-action) ─────────────────────────────────────────
    elif t == 'course-of-action' and is_valid(obj):
        mitigations.append({
            'stix_id':       obj['id'],
            'mitigation_id': get_mitre_id(obj),
            'name':          obj.get('name', ''),
            'description':   truncate(obj.get('description', '')),
        })

# =============================================================================
# Pass 2: 자연키 룩업 테이블 생성
#
# n8n에서 stix_id 대신 사람이 읽을 수 있는 키(technique_id, name 등)로
# MATCH 할 수 있도록 stix_id → (key_field, key_value) 매핑을 사전에 계산.
#
# 각 노드 타입별 primary key:
#   Technique       → technique_id  (T-코드, Incidents와 공유)
#   Tactic          → tactic_id     (TA-코드)
#   ThreatActor     → name          (Incidents attribution과 공유)
#   Malware         → name          (URLhaus threat/tag와 공유)
#   Tool            → name
#   Mitigation      → mitigation_id (M-코드)
# =============================================================================
print("  [2/3] 자연키 룩업 및 관계 생성 중...")

natural_key = {}   # stix_id → (field_name, field_value)
tactic_id_by_stix = {}  # tactic stix_id → tactic_id (TA-코드)

for obj in objects:
    t       = obj.get('type', '')
    stix_id = obj.get('id', '')
    if not stix_id:
        continue

    if t == 'attack-pattern' and is_valid(obj):
        tech_id = get_mitre_id(obj)
        if tech_id:
            natural_key[stix_id] = ('technique_id', tech_id)

    elif t == 'x-mitre-tactic':
        tac_id = get_mitre_id(obj)
        if tac_id:
            natural_key[stix_id] = ('tactic_id', tac_id)
            tactic_id_by_stix[stix_id] = tac_id

    elif t == 'intrusion-set' and is_valid(obj):
        name = obj.get('name', '')
        if name:
            natural_key[stix_id] = ('name', name)

    elif t == 'malware' and is_valid(obj):
        name = obj.get('name', '')
        if name:
            natural_key[stix_id] = ('name', name)

    elif t == 'tool' and is_valid(obj):
        name = obj.get('name', '')
        if name:
            natural_key[stix_id] = ('name', name)

    elif t == 'course-of-action' and is_valid(obj):
        mit_id = get_mitre_id(obj)
        if mit_id:
            natural_key[stix_id] = ('mitigation_id', mit_id)

# Technique → Tactic BELONGS_TO
for tech in techniques:
    src_key, src_val = 'technique_id', tech['technique_id']
    if not src_val:
        continue
    for phase in tech['tactic_phases']:
        tactic_stix_id = tactic_stix_by_shortname.get(phase)
        if not tactic_stix_id:
            continue
        tac_id = tactic_id_by_stix.get(tactic_stix_id)
        if tac_id:
            relationships.append({
                'neo4j_rel': 'BELONGS_TO',
                'src_label': 'Technique',
                'src_key':   src_key,
                'src_val':   src_val,
                'dst_label': 'Tactic',
                'dst_key':   'tactic_id',
                'dst_val':   tac_id,
            })

# =============================================================================
# Pass 3: STIX relationship 객체 처리
#          stix_id → 자연키로 변환하여 n8n이 단일 Cypher 템플릿으로 처리 가능하게
#
# n8n Cypher 템플릿 (단 하나):
#   MATCH (s:{{ src_label }} {{{ src_key }}: '{{ src_val }}'})
#   MATCH (d:{{ dst_label }} {{{ dst_key }}: '{{ dst_val }}'})
#   MERGE (s)-[:{{ neo4j_rel }}]->(d)
# =============================================================================
print("  [3/3] STIX 관계 변환 중...")

REL_MAP = {
    ('uses',          'intrusion-set',    'attack-pattern'): ('ThreatActor', 'Technique',  'USES_TECHNIQUE'),
    ('uses',          'intrusion-set',    'malware'):        ('ThreatActor', 'Malware',    'USES_MALWARE'),
    ('uses',          'intrusion-set',    'tool'):           ('ThreatActor', 'Tool',       'USES_TOOL'),
    ('uses',          'malware',          'attack-pattern'): ('Malware',     'Technique',  'USES_TECHNIQUE'),
    ('uses',          'malware',          'tool'):           ('Malware',     'Tool',       'USES_TOOL'),
    ('mitigates',     'course-of-action', 'attack-pattern'): ('Mitigation',  'Technique',  'MITIGATES'),
    ('subtechnique-of','attack-pattern',  'attack-pattern'): ('Technique',   'Technique',  'SUBTECHNIQUE_OF'),
}

for obj in objects:
    if obj.get('type') != 'relationship' or obj.get('revoked', False):
        continue

    rel_type = obj.get('relationship_type', '')
    src_ref  = obj.get('source_ref', '')
    dst_ref  = obj.get('target_ref', '')

    src_obj = id_map.get(src_ref, {})
    dst_obj = id_map.get(dst_ref, {})

    if not is_valid(src_obj) or not is_valid(dst_obj):
        continue

    key = (rel_type, src_obj.get('type', ''), dst_obj.get('type', ''))
    if key not in REL_MAP:
        continue

    src_nk = natural_key.get(src_ref)
    dst_nk = natural_key.get(dst_ref)
    if not src_nk or not dst_nk:
        continue  # 자연키 없는 항목 스킵 (기술 ID 없는 deprecated 등)

    src_label, dst_label, neo4j_rel = REL_MAP[key]
    src_key, src_val = src_nk
    dst_key, dst_val = dst_nk

    if not src_val or not dst_val:
        continue

    relationships.append({
        'neo4j_rel': neo4j_rel,
        'src_label': src_label,
        'src_key':   src_key,
        'src_val':   src_val,
        'dst_label': dst_label,
        'dst_key':   dst_key,
        'dst_val':   dst_val,
    })

# =============================================================================
# 파일 출력
# =============================================================================
output_files = [
    ('tactics.json',       tactics),
    ('techniques.json',    techniques),
    ('threat_actors.json', threat_actors),
    ('malware.json',       malware_list),
    ('tools.json',         tools),
    ('mitigations.json',   mitigations),
    ('relationships.json', relationships),
]

print("\n  출력 파일:")
for filename, data in output_files:
    path = os.path.join(out_dir, filename)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"    {filename:<22} {len(data):>5,} records")

PYEOF

echo "[MITRE] 완료!"
