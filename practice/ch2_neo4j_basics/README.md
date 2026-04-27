# CH2 Neo4j Basics

Neo4j를 독립적으로 기동하고, 사전 준비된 데이터셋을 Browser에서 직접 탐색하는 가장 기본 실습입니다.

---

## 준비사항

- `docker` / `docker compose`
- `.env.sample`을 복사해 `.env` 준비

현재 `.env`의 핵심 값:

- `ACTIVE_DATASET`
- `NEO4J_USERNAME`
- `NEO4J_PASSWORD`

`ACTIVE_DATASET`은 `../dataset`에 준비된 데이터셋 중 하나를 선택합니다.

예시:

- `stackoverflow`
- `pole`
- `network-management`
- `recommendations`

---

## 빠른 시작

```bash
cd practice/ch2_neo4j_basics
cp .env.sample .env
docker compose up -d
```

접속 주소:

- Neo4j Browser: http://localhost:7474
- Bolt: `bolt://localhost:7687`

종료:

```bash
docker compose down
```

---

## 서비스 구성

- `neo4j`
  Neo4j 단일 컨테이너

마운트되는 공통 경로:

- `../../dataset`
- `../../neo4j/import`
- `../../neo4j/plugins`

`neo4j_init.sh`는 컨테이너 시작 시 선택한 데이터셋을 반영하도록 돕는 초기화 스크립트입니다.

---

## 실습 목표

- Neo4j Browser 접속
- 데이터셋이 정상 로드되었는지 확인
- 기본 Cypher 조회 수행

예시 쿼리:

```cypher
MATCH (n) RETURN labels(n), count(*) LIMIT 10
```

```cypher
MATCH (n)-[r]->(m) RETURN type(r), count(*) LIMIT 10
```

---

## 성공 확인

- Browser 로그인이 된다.
- `MATCH (n)` 계열 조회가 정상 동작한다.
- `ACTIVE_DATASET`에 따라 노드/관계가 비어 있지 않다.

다음 챕터에서는 이 Neo4j 환경 위에 MCP와 챗 인터페이스를 붙여 자연어 탐색으로 확장합니다.
