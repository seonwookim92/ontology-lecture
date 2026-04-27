#!/bin/bash
set -e

# 데이터베이스 메타데이터가 없으면(즉, 비어있는 볼륨이면) 로드 실행
if [ ! -f /data/databases/neo4j/metadata ] && [ -n "$ACTIVE_DATASET" ]; then
    echo "--- Preparing to load dataset: $ACTIVE_DATASET ---"
    
    # 1. 특정 데이터셋 폴더에서 -50.dump 파일 탐색 (가장 최신 버전용 파일)
    SRC_DUMP=$(ls /dataset/$ACTIVE_DATASET/data/*-50.dump 2>/dev/null | head -n 1)

    if [ -n "$SRC_DUMP" ]; then
        echo "--- Found dump: $SRC_DUMP ---"
        
        # 2. 임시 폴더 생성 및 로드용 이름으로 심볼릭 링크 생성
        # Neo4j 5.x의 --from-path는 폴더 내에서 <DB이름>.dump 파일을 찾습니다.
        mkdir -p /tmp/neo4j-load
        ln -sf "$SRC_DUMP" /tmp/neo4j-load/neo4j.dump
        
        # 3. 로드 실행
        echo "--- Loading dump into 'neo4j' database ---"
        neo4j-admin database load neo4j --from-path=/tmp/neo4j-load --overwrite-destination=true
        
        # 4. 권한 설정 (생성된 파일들의 소유권을 neo4j 사용자로 변경)
        echo "--- Cleaning up permissions ---"
        chown -R neo4j:neo4j /data
        
        echo "--- Initialization complete ---"
    else
        echo "--- WARNING: No -50.dump file found for '$ACTIVE_DATASET'. Skipping load. ---"
    fi
fi

# 원래 Neo4j 엔트리포인트 실행
exec /startup/docker-entrypoint.sh neo4j
