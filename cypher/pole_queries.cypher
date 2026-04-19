// [Crime Investigation] 1. 전체 스키마 시각화
CALL db.schema.visualization();

// [Crime Investigation] 2. 특정 인물(예: 'Alexander') 주변의 관계망 확인
MATCH (p:Person {surname: 'Alexander'})-[r]-(n)
RETURN p, r, n;

// [Crime Investigation] 3. 범죄가 가장 많이 일어난 위치 상위 10곳
MATCH (l:Location)<-[:OCCURRED_AT]-(c:Crime)
RETURN l.address AS Address, count(c) AS CrimeCount
ORDER BY CrimeCount DESC LIMIT 10;

// [Crime Investigation] 4. 두 인물 사이의 최단 경로 찾기 (수사 필수 쿼리)
MATCH (p1:Person {surname: 'Powell'}), (p2:Person {surname: 'Walker'})
MATCH path = shortestPath((p1)-[*..5]-(p2))
RETURN path;
