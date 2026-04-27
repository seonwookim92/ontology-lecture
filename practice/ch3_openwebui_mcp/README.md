# CH3 Open WebUI + Neo4j MCP

Neo4j에 MCP 서버를 연결하고, Open WebUI를 통해 자연어로 그래프를 조회하는 실습입니다.  
이 챕터의 핵심은 “LLM이 직접 Cypher를 쓰되, 스키마를 먼저 확인하고 도구를 통해 실행하게 만드는 흐름”입니다.

---

## 준비사항

- `docker` / `docker compose`
- `../utils/mcp` 경로에 Neo4j MCP 코드 존재
- `.env`의 LLM 연결 정보 확인

주요 환경 변수:

- `ACTIVE_DATASET`
- `NEO4J_USERNAME`
- `NEO4J_PASSWORD`
- `VLLM_BASE_URL`
- `LLM_API_KEY`

---

## 빠른 시작

```bash
cd practice/ch3_openwebui_mcp
docker compose up -d --build
```

접속 주소:

- Neo4j Browser: http://localhost:7474
- Open WebUI: http://localhost:3000
- MCPO OpenAPI debug: http://localhost:8081

종료:

```bash
docker compose down
```

---

## 서비스 구성

- `neo4j`
  데이터셋이 로드된 그래프 DB
- `neo4j-mcp`
  Neo4j MCP 서버
- `mcpo`
  MCP를 OpenAPI/HTTP 형태로 노출하는 브릿지
- `open-webui`
  사용자가 직접 질문하는 챗 UI

관련 파일:

- `docker-compose.yml`
- `mcpo_config.json`
- `system-prompt.txt`

`system-prompt.txt`는 모델이 다음 규칙을 따르도록 유도합니다.

- 스키마 먼저 확인
- 단순한 Cypher 사용
- LIMIT 기본 적용
- 실제 실행한 쿼리를 보여주고 한국어로 설명

---

## 실습 흐름

1. Open WebUI에 접속
2. Neo4j 관련 툴이 연결된 모델/에이전트 구성 확인
3. 스키마 기반 질문 수행
4. 결과와 사용된 Cypher를 함께 확인

추천 질문 예시:

- `현재 그래프에 어떤 노드 라벨이 있는지 보여줘`
- `가장 많이 연결된 노드 10개를 찾아줘`
- `추천 데이터셋에서 액션 영화 10개를 보여줘`

---

## 성공 확인

- Open WebUI에서 질문이 정상 전송된다.
- 모델이 도구를 사용해 Neo4j를 조회한다.
- 답변에 실제 Cypher와 결과 설명이 함께 나온다.

다음 챕터에서는 같은 MCP 기반 접근을 n8n 워크플로우와 웹앱 백엔드 형태로 확장합니다.
