# Practice Guide

이 디렉토리는 온톨로지·지식그래프 수업용 실습을 챕터별로 분리해 제공합니다.  
각 챕터는 독립 실행이 가능하며, 앞 챕터의 개념을 다음 챕터에서 확장하는 구조입니다.

## 학습 순서

1. [ch2_neo4j_basics](./ch2_neo4j_basics/README.md)
   Neo4j 기동, 데이터셋 로드, Browser에서 기본 Cypher 확인
2. [ch3_openwebui_mcp](./ch3_openwebui_mcp/README.md)
   Open WebUI와 Neo4j MCP를 연결해 자연어로 그래프 탐색
3. [ch4_n8n_automation](./ch4_n8n_automation/README.md)
   n8n 기반 데이터 적재, 워크플로우 자동화, 간단한 웹앱 백엔드 구성
4. [ch5_real_challenge](./ch5_real_challenge/README.md)
   외부 CTI 데이터와 Incident를 연결한 실전형 보안 지식그래프 구축

## 챕터 구성

- `ch2_neo4j_basics`
  Neo4j 단독 환경으로 시작하는 기본 실습
- `ch3_openwebui_mcp`
  Open WebUI + MCPO + Neo4j MCP 기반 챗 인터페이스 실습
- `ch4_n8n_automation`
  n8n을 활용한 적재/조회 자동화와 데모 프론트 실습
- `ch5_real_challenge`
  실제 외부 위협 인텔리전스 소스를 연결한 최종 통합 실습

## 공통 준비사항

- `docker` / `docker compose`
- `curl`
- `python3`
- 챕터별 `.env` 확인

일부 챕터는 `practice/` 바깥의 공통 자산을 참조합니다.

- `../dataset`
- `../neo4j`
- `../utils/mcp`

특히 `ch3`, `ch4`, `ch5`는 vLLM 또는 OpenAI 호환 API 엔드포인트 설정이 필요할 수 있습니다.

## 공통 실행 흐름

1. 원하는 챕터 디렉토리로 이동
   ```bash
   cd practice/ch3_openwebui_mcp
   ```
2. 필요하면 샘플 파일을 복사해 `.env` 생성
   ```bash
   cp .env.sample .env
   ```
3. `.env` 값 확인
4. 서비스 실행
   ```bash
   docker compose up -d --build
   ```
5. 실습 종료
   ```bash
   docker compose down
   ```

## 주의사항

- 포트 충돌을 피하려면 한 번에 하나의 챕터만 실행하는 편이 안전합니다.
- `ch3`, `ch4`, `ch5`는 Neo4j MCP 빌드가 포함되므로 첫 실행이 오래 걸릴 수 있습니다.
- `ch5`는 데이터 수집 스크립트를 먼저 실행해야 워크플로우 import가 수월합니다.

각 챕터별 상세 절차는 해당 디렉토리의 `README.md`를 기준으로 진행하세요.
