#!/usr/bin/env bash
# =============================================================================
# fetch_urlhaus.sh — URLhaus 악성 URL 피드 다운로드 및 전처리
#
# 출처 : https://urlhaus.abuse.ch (abuse.ch)
#
# 출력 (data/urlhaus/):
#   indicators.json  — 악성 URL 목록
#                       각 항목에 host(IP/도메인), cve_ids(태그에서 추출),
#                       malware_name(threat 필드에서 추출) 포함
#
# 교차 연결 정보 (n8n에서 사용):
#   cve_ids     → Vulnerability 노드와 EXPLOITS 관계 생성 가능
#   malware_name → Malware 노드와 INDICATES 관계 생성 가능
# =============================================================================
set -euo pipefail

DATA_DIR="${1:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")/data}"
OUT_DIR="$DATA_DIR/urlhaus"
RAW_FILE="$OUT_DIR/_raw_urlhaus.csv"
FORCE="${2:-}"
# 현재 온라인 상태인 URL만 포함 (경량 버전)
URLHAUS_URL="https://urlhaus.abuse.ch/downloads/csv_online/"

mkdir -p "$OUT_DIR"

# ── 다운로드 ──────────────────────────────────────────────────────────────────
if [[ ! -f "$RAW_FILE" ]] || [[ "$FORCE" == "--force" ]]; then
    echo "[URLhaus] 악성 URL 피드 다운로드 중..."
    # --compressed: 서버가 gzip으로 응답할 경우 자동 압축 해제
    curl -fSL --compressed --progress-bar "$URLHAUS_URL" -o "$RAW_FILE"
    echo "[URLhaus] 다운로드 완료: $(du -sh "$RAW_FILE" | cut -f1)"
else
    echo "[URLhaus] 캐시된 파일 사용: $(du -sh "$RAW_FILE" | cut -f1)"
fi

echo "[URLhaus] 인디케이터 파싱 및 정규화 중..."

export URLHAUS_OUT_DIR="$OUT_DIR"
export URLHAUS_RAW_FILE="$RAW_FILE"

python3 << 'PYEOF'
import csv, json, os, re
import ipaddress
from urllib.parse import urlparse

out_dir  = os.environ['URLHAUS_OUT_DIR']
raw_path = os.environ['URLHAUS_RAW_FILE']

# ── 상수 ──────────────────────────────────────────────────────────────────────
# URLhaus CSV 컬럼 순서 (헤더 행이 # 주석으로 처리되므로 직접 정의)
HEADERS = ['id', 'date_added', 'url', 'url_status', 'last_online',
           'threat', 'tags', 'urlhaus_link', 'reporter']

# threat 필드 — 일반 카테고리 (악성코드명 아님)
GENERIC_THREATS = {
    'malware_download', 'phishing', 'botnet_cc', 'exploit',
    'scanner', 'cve_exploit', 'none', ''
}

# 태그에서 악성코드명을 추출할 때 제외할 일반 태그
GENERIC_TAGS = {
    'exe', 'dll', 'elf', 'jar', 'ps1', 'vbs', 'bat', 'js', 'msi',
    'none', 'null', 'unknown', 'malware', 'loader',
}

CVE_RE    = re.compile(r'CVE-\d{4}-\d+', re.IGNORECASE)
DASH_IP_RE= re.compile(r'^\d{1,3}(?:-\d{1,3}){3}$')  # 태그 내 하이픈 IP 제외
DOT_IP_RE = re.compile(r'^\d{1,3}(?:\.\d{1,3}){3}$') # 태그 내 도트 IP 제외
PORT_RE   = re.compile(r'^\d+$')                        # 순수 숫자 제외

# ── 헬퍼: URL에서 호스트 추출 ──────────────────────────────────────────────────
def parse_host(url):
    """(host, host_type) 반환. host_type: 'ip' | 'domain' | None"""
    try:
        parsed = urlparse(url if '://' in url else 'http://' + url)
        host = (parsed.hostname or '').strip('[]')  # IPv6 대괄호 제거
        if not host:
            return None, None
        try:
            ipaddress.ip_address(host)
            return host, 'ip'
        except ValueError:
            return host.lower(), 'domain'
    except Exception:
        return None, None

# ── CSV 파싱 ──────────────────────────────────────────────────────────────────
indicators = []
skipped = 0

with open(raw_path, newline='', encoding='utf-8', errors='replace') as f:
    reader = csv.reader(f)
    for row in reader:
        # 주석 행 스킵 (# 로 시작)
        if not row or str(row[0]).startswith('#'):
            continue
        if len(row) < len(HEADERS):
            skipped += 1
            continue

        record = {k: v.strip() for k, v in zip(HEADERS, row)}

        url = record.get('url', '').strip()
        if not url:
            skipped += 1
            continue

        # 호스트 추출 (IP or 도메인)
        host, host_type = parse_host(url)

        # 태그에서 CVE ID 추출
        tags_str = record.get('tags', '') or ''
        raw_tags = [t.strip() for t in tags_str.split(',') if t.strip()]
        cve_ids = [m.upper() for m in CVE_RE.findall(tags_str)]

        # ── 악성코드명 추출 (우선순위: threat 필드 → tags) ───────────────────────
        # 1) threat 필드가 구체적인 악성코드명인 경우 (예: 'Emotet', 'TrickBot')
        threat_raw   = record.get('threat', '').strip()
        threat_lower = threat_raw.lower()
        if threat_lower and threat_lower not in GENERIC_THREATS:
            malware_name = threat_raw
        else:
            # 2) tags에서 악성코드명처럼 보이는 것 추출
            #    - CVE ID, 순수 숫자, IP 형태, 파일 확장자, 일반 태그 제외
            #    - 대문자로 시작하거나 알려진 패턴인 것 선택
            candidate = None
            for tag in raw_tags:
                tl = tag.lower()
                if (tag in ('None', 'none', '') or
                    tl in GENERIC_TAGS or
                    CVE_RE.match(tag) or
                    DASH_IP_RE.match(tag) or
                    DOT_IP_RE.match(tag) or
                    PORT_RE.match(tag) or
                    tag[0].isdigit()):          # 숫자 시작 태그 제외 (IP, VT 수치 등)
                    continue
                # 대문자 시작 혹은 혼합 대소문자 → 악성코드 패밀리명 가능성 높음
                if tag[0].isupper() or (len(tag) > 3 and not tag.islower()):
                    candidate = tag
                    break
            malware_name = candidate

        indicators.append({
            'value':         url,          # 고유 키
            'indicator_type':'url',
            'status':        record.get('url_status', '').strip(),
            'threat':        threat_raw,
            'date_added':    record.get('date_added', '').strip(),
            # 호스트 정보 (n8n에서 Host 노드 생성 및 HOSTED_ON 관계에 활용)
            'host':          host,
            'host_type':     host_type,    # 'ip' | 'domain' | null
            # 교차 연결 포인트
            'cve_ids':       cve_ids,      # → Vulnerability 노드와 EXPLOITS 관계
            'malware_name':  malware_name, # → Malware 노드와 INDICATES 관계
            'tags':          raw_tags,
        })

print(f"  파싱 완료: {len(indicators):,} 개 인디케이터 (스킵: {skipped})")

# ── 출력 ──────────────────────────────────────────────────────────────────────
out_path = os.path.join(out_dir, 'indicators.json')
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(indicators, f, ensure_ascii=False, indent=2)

print(f"  출력: {out_path}")

# ── 통계 ──────────────────────────────────────────────────────────────────────
with_cve     = sum(1 for i in indicators if i['cve_ids'])
with_malware = sum(1 for i in indicators if i['malware_name'])
ip_hosts     = sum(1 for i in indicators if i['host_type'] == 'ip')
domain_hosts = sum(1 for i in indicators if i['host_type'] == 'domain')

print(f"  - CVE 교차 연결 가능: {with_cve:,} 개")
print(f"  - Malware 교차 연결 가능: {with_malware:,} 개")
print(f"  - IP 호스트: {ip_hosts:,} / 도메인 호스트: {domain_hosts:,}")

PYEOF

echo "[URLhaus] 완료!"
