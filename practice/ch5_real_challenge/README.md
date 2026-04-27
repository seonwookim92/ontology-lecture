# CH5 Real Challenge — 실전 보안 지식 그래프

ch4에서 익힌 n8n + Neo4j + text2cypher 패턴을 바탕으로,  
실제 외부 위협 인텔리전스 데이터를 연결한 풀스케일 보안 지식 그래프를 구축하는 실습입니다.

---

## 사전 준비

| 도구 | 용도 | 설치 확인 |
|------|------|-----------|
| `curl` | 외부 소스 다운로드 | `curl --version` |
| `python3` | 데이터 전처리 (표준 라이브러리만 사용) | `python3 --version` |
| `docker` / `docker compose` | Neo4j + n8n 환경 | `docker --version` |

> Python 추가 패키지 설치 **불필요** — `json`, `csv`, `re`, `urllib` 등 표준 라이브러리만 사용합니다.

---

## 빠른 시작

### 1단계 — 데이터 수집 (한 번만 실행)

```bash
bash scripts/fetch_all.sh
```

4개 외부 소스에서 데이터를 내려받고 전처리합니다.  
총 소요 시간: **약 2–3분** (MITRE ~44MB 다운로드 포함)

```
==============================================
  CH5 Real Challenge — Data Fetch & Preprocess
==============================================

[MITRE]    ATT&CK 번들 다운로드 중... (~43MB)
[KEV]      CISA KEV 카탈로그 다운로드 중...
[URLhaus]  악성 URL 피드 다운로드 중...
[Incidents] 사건 데이터 다운로드 중...

==============================================
  완료! 생성된 파일 목록
==============================================
  [   320 records |  776K]  data/incidents/incidents.json
  [  1583 records |  2.0M]  data/kev/vulnerabilities.json
  [   693 records |  392K]  data/mitre/malware.json
  ...
```

> 재실행 시 이미 다운로드된 파일은 **캐시를 사용**하므로 빠릅니다.  
> 항상 최신 데이터를 받으려면 `--force` 옵션을 사용하세요:
> ```bash
> bash scripts/fetch_all.sh --force
> ```

### 2단계 — 환경 기동 (docker compose)

```bash
# ch5 디렉토리에서 실행 (docker-compose.yml 준비 후)
cp .env.sample .env
docker compose up -d
```

- Neo4j Browser: http://localhost:7474
- n8n: http://localhost:5678
- Graph Viewer: http://localhost:8087

### 3단계 — n8n 워크플로우 임포트 및 실행

`workflows/` 디렉토리의 JSON 파일을 n8n에 순서대로 임포트합니다:

| 순서 | 파일 | 역할 |
|------|------|------|
| 1 | `00_setup_constraints.json` | Neo4j 제약 조건 / 인덱스 생성 |
| 2 | `01_load_mitre.json` | MITRE ATT&CK 노드 + 관계 적재 |
| 3 | `02_load_kev.json` | CISA KEV 취약점 적재 |
| 4 | `03_load_urlhaus.json` | URLhaus 인디케이터 적재 |
| 5 | `04_load_incidents.json` | 사건 데이터 + 교차 연결 |
| 6 | `05_text2cypher_chatbot.json` | 자연어 질의 챗봇 |
| 7 | `06_actor_attribution_form.json` | 폼 기반 Threat Actor 추정 |
| 8 | `07_visualize_graph_api.json` | 그래프 시각화용 API |

---

## 데이터 소스

| 소스 | URL | 레코드 수 | 설명 |
|------|-----|-----------|------|
| **MITRE ATT&CK** | github.com/mitre/cti | ~1,700 nodes | 기법, 전술, APT 그룹, 악성코드, 도구, 완화 |
| **CISA KEV** | cisa.gov | ~1,583 | 실제 악용 확인된 CVE 취약점 목록 |
| **URLhaus** | urlhaus.abuse.ch | ~12,000 | 현재 활성 악성 URL 피드 |
| **Incidents** | GitHub Gist | 320 | 한국 주요 사이버 사건 (가상) |

---

## 생성 파일 구조

```
data/
├── mitre/
│   ├── tactics.json          # 14개 전술 (TA-코드)
│   ├── techniques.json       # 691개 기법 (T-코드, 하위기법 포함)
│   ├── threat_actors.json    # 172개 APT 그룹 (aliases 포함)
│   ├── malware.json          # 693개 악성코드 패밀리
│   ├── tools.json            # 91개 해킹/정보수집 도구
│   ├── mitigations.json      # 44개 완화 조치 (M-코드)
│   └── relationships.json    # 18,109개 관계 (Neo4j 라벨 사전 매핑)
├── kev/
│   └── vulnerabilities.json  # 1,583개 취약점 (CVE ID 기준)
├── urlhaus/
│   └── indicators.json       # 12,363개 악성 URL (host/CVE/malware 추출)
└── incidents/
    └── incidents.json        # 320개 사건 (attack_flow 단계별 T-코드 파싱)
```

> `data/` 내 파일은 `.gitignore`에 의해 git에 포함되지 않습니다.  
> 실습 시작 전 반드시 `bash scripts/fetch_all.sh`를 먼저 실행하세요.

---

## 데이터 소스 간 연결 구조

```
MITRE ──────────────────────────────────────────────
  ThreatActor ←── Incidents (attribution.group_name)
  Technique   ←── Incidents (attack_flow T-코드)
  Malware     ←── Incidents (related_entity type=Malware)
              ←── URLhaus  (malware_name from tags)

KEV ────────────────────────────────────────────────
  Vulnerability ←── Incidents (related_entity type=Vulnerability)
               ←── URLhaus  (cve_ids from tags)

URLhaus ────────────────────────────────────────────
  Indicator ←── Incidents (related_entity type=Indicator)
```

---

## n8n 파일 경로

docker compose에서 `./data` 디렉토리가 n8n 컨테이너의 `/home/node/.n8n-files/`에 마운트됩니다.  
n8n 워크플로우 내 파일 읽기 경로:

```
/home/node/.n8n-files/mitre/tactics.json
/home/node/.n8n-files/mitre/techniques.json
/home/node/.n8n-files/mitre/threat_actors.json
/home/node/.n8n-files/mitre/malware.json
/home/node/.n8n-files/mitre/tools.json
/home/node/.n8n-files/mitre/mitigations.json
/home/node/.n8n-files/mitre/relationships.json
/home/node/.n8n-files/kev/vulnerabilities.json
/home/node/.n8n-files/urlhaus/indicators.json
/home/node/.n8n-files/incidents/incidents.json
```

---

## Graph Viewer

`07_visualize_graph_api.json`는 n8n을 그래프 시각화 API로 사용하고,  
`graph-viewer/` 디렉토리는 별도 정적 프론트엔드로 동작합니다.

### 사용 순서

1. `00 ~ 04` 워크플로우로 Neo4j 그래프 적재
2. `07_visualize_graph_api.json`를 n8n에 import 후 활성화
3. `docker compose up -d`
4. `http://localhost:8087` 접속
5. 좌측의 `Fetch Incidents` 버튼으로 사건 목록을 먼저 불러온 뒤 그래프를 탐색

### 제공 기능

- Incident 목록 조회
- Incident 선택 후 1~2 hop 초기 subgraph 시각화
- 노드 클릭 시 속성 및 연결 미리보기 확인
- neighbor label count 조회
- 선택한 label 기준 incremental expand

### Webhook 경로 주의

프론트는 아래 두 endpoint를 순서대로 시도합니다.

- `http://localhost:5678/webhook/graph-viewer-api`
- `http://localhost:5678/webhook-test/graph-viewer-api`

권장 방식은 `07_visualize_graph_api.json` 워크플로우를 `Active` 상태로 두고  
운영 경로인 `/webhook/graph-viewer-api`를 사용하는 것입니다.  
`/webhook-test/...`는 n8n 에디터 테스트 모드에서만 일시적으로 동작할 수 있습니다.

### 프론트 디렉토리

```
graph-viewer/
├── index.html
├── app.js
├── styles.css
└── nginx.conf
```

---

## relationships.json 구조

MITRE의 stix_id 기반 참조를 Python 전처리 단계에서 모두 해석하여,  
n8n 워크플로우는 **단일 Cypher 템플릿**으로 모든 관계를 처리할 수 있습니다.

```json
{
  "neo4j_rel":   "USES_TECHNIQUE",
  "src_label":   "ThreatActor",
  "src_stix_id": "intrusion-set--abc123...",
  "dst_label":   "Technique",
  "dst_stix_id": "attack-pattern--xyz456..."
}
```

n8n Cypher 템플릿:
```cypher
MATCH (src:{{ $json.src_label }} {stix_id: '{{ $json.src_stix_id }}'})
MATCH (dst:{{ $json.dst_label }} {stix_id: '{{ $json.dst_stix_id }}'})
MERGE (src)-[:{{ $json.neo4j_rel }}]->(dst)
```

포함된 관계 타입:

| `neo4j_rel` | 소스 → 타겟 | 건수 |
|-------------|------------|------|
| `BELONGS_TO` | Technique → Tactic | ~700 |
| `USES_TECHNIQUE` | ThreatActor/Malware → Technique | ~5,000 |
| `USES_MALWARE` | ThreatActor → Malware | ~1,000 |
| `USES_TOOL` | ThreatActor/Malware → Tool | ~500 |
| `MITIGATES` | Mitigation → Technique | ~2,000 |
| `SUBTECHNIQUE_OF` | Technique → Technique | ~400 |

---

## 스크립트 옵션

```bash
# 전체 fetch (캐시 사용)
bash scripts/fetch_all.sh

# 전체 강제 재다운로드 (최신 데이터)
bash scripts/fetch_all.sh --force

# 개별 소스만 실행
bash scripts/fetch_mitre.sh data
bash scripts/fetch_kev.sh data
bash scripts/fetch_urlhaus.sh data
bash scripts/fetch_incidents.sh data

# 개별 소스 강제 재다운로드
bash scripts/fetch_mitre.sh data --force
```
