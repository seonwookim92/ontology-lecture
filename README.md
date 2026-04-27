# Ontology Practice

온톨로지·지식그래프 수업을 위한 실습 저장소입니다.  
이 루트 디렉토리는 공통 실행 환경, 데이터셋 서브모듈, Neo4j 초기 적재 구조를 관리하고, 챕터별 실습 자료는 [`practice/`](./practice/README.md) 아래에서 진행합니다.

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
- `docker-compose.yml`
  루트 공통 Neo4j 실행 정의
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

## 공통 실행 환경

루트 환경은 챕터 실습에서 공통으로 참조하는 Neo4j 데이터베이스 기동용입니다.

준비물:

- `git`
- `docker`
- `docker compose`

환경 변수 파일을 먼저 준비합니다.

```bash
cp .env.sample .env
```

`.env`에서 `ACTIVE_DATASET`을 아래 중 하나로 지정할 수 있습니다.

- `stackoverflow`
- `pole`
- `network-management`
- `recommendations`

예시:

```env
ACTIVE_DATASET=recommendations
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=testpassword
```

## Neo4j 실행과 데이터 적재

루트의 `docker-compose.yml`은 Neo4j 컨테이너 1개를 실행하며, `ACTIVE_DATASET` 값에 따라 데이터셋을 분기합니다.

```bash
docker compose up -d
```

접속 정보:

- Neo4j Browser: `http://localhost:7474`
- Bolt: `bolt://localhost:7687`

초기 기동 시 `neo4j_init.sh`가 다음 순서로 동작합니다.

1. 현재 데이터 볼륨이 비어 있는지 확인
2. `dataset/<ACTIVE_DATASET>/data/` 아래의 `*-50.dump` 파일 탐색
3. dump를 `neo4j` 데이터베이스로 로드
4. 이후 Neo4j 서버 시작

즉, 같은 데이터 볼륨이 이미 존재하면 dump를 다시 적재하지 않습니다.

## 데이터셋 변경 또는 초기화

다른 데이터셋으로 바꾸거나 완전히 새로 적재하려면 기존 볼륨을 지운 뒤 다시 실행해야 합니다.

```bash
docker compose down -v
```

그 다음 `.env`의 `ACTIVE_DATASET` 값을 변경하고 다시 기동합니다.

```bash
docker compose up -d
```

`-v` 없이 종료하면 기존 볼륨이 유지되어 이전 데이터베이스 상태가 그대로 남습니다.

## 데이터베이스/플러그인 관련 참고

- `neo4j/data`, `neo4j/logs`, `neo4j/plugins`는 로컬 실행 중 생성되거나 갱신되는 작업 디렉토리입니다.
- 루트 Compose 설정은 APOC, Graph Data Science 플러그인을 사용합니다.
- `utils/mcp`는 MCP 실습에서 참조하는 공용 소스이며, 상세 사용법은 각 챕터 문서를 따르세요.

## 실습 진행 위치

챕터별 목표, 준비사항, 실행 절차는 루트가 아니라 [`practice/README.md`](./practice/README.md)와 각 챕터의 `README.md`를 기준으로 진행하면 됩니다.
