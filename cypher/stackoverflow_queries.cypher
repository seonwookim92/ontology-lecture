// [StackOverflow] 1. 가장 많이 질문된 태그 상위 10개
MATCH (t:Tag)<-[:TAGGED]-(q:Question)
RETURN t.name AS Tag, count(q) AS Count
ORDER BY Count DESC LIMIT 10;

// [StackOverflow] 2. 'neo4j' 태그가 달린 최신 질문들
MATCH (t:Tag {name: 'neo4j'})<-[:TAGGED]-(q:Question)
RETURN q.title, q.link
LIMIT 10;

// [StackOverflow] 3. 채택된 답변(Accepted Answer)이 있는 질문들 비율 확인
MATCH (q:Question)
OPTIONAL MATCH (q)-[r:ANSWERED]->(a:Answer {is_accepted: true})
RETURN count(q) AS TotalQuestions, count(a) AS QuestionsWithAcceptedAnswer;

// [StackOverflow] 4. 특정 태그 조합(예: neo4j + cypher) 찾기
MATCH (t1:Tag {name: 'neo4j'})<-[:TAGGED]-(q:Question)-[:TAGGED]->(t2:Tag {name: 'cypher'})
RETURN q.title, q.link;
