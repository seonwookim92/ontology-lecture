# CH4 n8n Automation

n8n을 이용해 Neo4j 그래프를 자동 적재하고, MCP/MCPO를 통해 읽기·쓰기 쿼리를 호출하는 실습입니다.

---

## 준비사항

- `docker` / `docker compose`
- `../utils/mcp` 경로에 Neo4j MCP 코드 존재
- `.env.sample`을 복사해 `.env` 준비
- `.env` 설정 확인

주요 환경 변수:

- `ACTIVE_DATASET`
- `NEO4J_USERNAME`
- `NEO4J_PASSWORD`
- `VLLM_BASE_URL`
- `LLM_API_KEY`

---

## 빠른 시작

```bash
cd practice/ch4_n8n_automation
cp .env.sample .env
docker compose up -d --build
```

접속 주소:

- Neo4j Browser: http://localhost:7474
- n8n: http://localhost:5678
- MCPO OpenAPI debug: http://localhost:8082

종료:

```bash
docker compose down
```

---

## 현재 포함된 자산

워크플로우:

- `workflows/00_explore_neo4j.json`
  n8n Chat Trigger + MCP 기반 Neo4j 탐색
- `workflows/01_data_ingestion.json`
  CSV/JSON 보안 데이터를 정규화해 Neo4j로 적재하는 실습

데이터:

- `data/`
  n8n 컨테이너의 `/home/node/.n8n-files`로 마운트되는 입력 파일 디렉토리

---

## 워크플로우 실습 순서

### 1. 그래프 탐색

`00_explore_neo4j.json`를 import합니다.

목적:

- 런타임 스키마 조회
- 자연어를 Cypher로 변환
- `read-cypher`, `write-cypher` 툴 호출

이 워크플로우는 교육 목적에 맞게:

- 실제 사용한 쿼리 노출
- 한국어 설명
- 스키마 우선 확인

흐름으로 구성되어 있습니다.

### 2. 데이터 적재

`01_data_ingestion.json`를 import합니다.

목적:

- CSV/JSON 입력 파일 읽기
- 이벤트, 사용자, IP, 도메인, 위협 인텔리전스 노드 정규화
- 제약 조건 생성 후 그래프 적재

이 워크플로우는 수동 실행형(`Manual Trigger`)이며, 적재용 예제로 보는 것이 맞습니다.

---

## 성공 확인

- n8n에서 워크플로우 import가 정상 동작한다.
- `00_explore_neo4j.json`로 채팅형 탐색이 가능하다.
- `01_data_ingestion.json` 실행 시 적재용 Cypher 호출이 발생한다.

다음 챕터에서는 n8n을 중심으로 외부 CTI 데이터를 모으고, 실전형 보안 지식그래프를 구축합니다.
