# Ontology Practice

온톨로지·지식그래프 수업을 위한 실습 저장소입니다.  
이 루트 디렉토리는 공통 데이터셋, Neo4j 초기 적재 구조, MCP 관련 소스를 관리하고, 챕터별 실습 자료와 실행은 [`practice/`](./practice/README.md) 아래에서 진행합니다.

## 저장소 구성

- [`practice/`](./practice/README.md)
  챕터별 실습 가이드와 실습용 리소스
- `dataset/`
  Neo4j 예제 데이터셋 서브모듈 모음
- `utils/mcp/`
  Neo4j MCP 서버 소스 서브모듈
- `neo4j/`
  공통 Neo4j 실행에 사용하는 import, plugin, 데이터 볼륨 경로
- `cypher/`
  수업 중 참고하거나 재사용할 수 있는 Cypher 쿼리
- `neo4j_init.sh`
  선택한 데이터셋 dump를 최초 기동 시 자동 적재하는 초기화 스크립트

## 서브모듈 안내

이 저장소는 일부 디렉토리를 Git submodule로 관리합니다.

- `dataset/network-management`
- `dataset/pole`
- `dataset/recommendations`
- `dataset/stackoverflow`
- `utils/mcp`

처음 clone할 때는 submodule까지 함께 받아야 합니다.

```bash
git clone --recursive <repository-url>
```

이미 clone한 뒤라면 아래 명령으로 submodule을 초기화하세요.

```bash
git submodule update --init --recursive
```

서브모듈이 비어 있으면 데이터셋 dump나 MCP 관련 소스가 없어 일부 실습이 정상 동작하지 않습니다.

## 데이터베이스/플러그인 관련 참고

- `neo4j/data`, `neo4j/logs`, `neo4j/plugins`는 로컬 실행 중 생성되거나 갱신되는 작업 디렉토리입니다.
- 각 챕터의 Compose 설정은 APOC, Graph Data Science 플러그인을 사용합니다.
- `utils/mcp`는 MCP 실습에서 참조하는 공용 소스이며, 상세 사용법은 각 챕터 문서를 따르세요.

## 실습 진행 위치

챕터별 목표, 준비사항, 환경 변수 파일 생성, 실행 절차는 루트가 아니라 [`practice/README.md`](./practice/README.md)와 각 챕터의 `README.md`를 기준으로 진행하면 됩니다.
