#!/usr/bin/env python3
"""
CH5 n8n 워크플로우 JSON 생성기
실행: python3 scripts/generate_workflows.py
출력: workflows/*.json
"""
import json, uuid, os, math

OUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'workflows')
os.makedirs(OUT_DIR, exist_ok=True)

MCPO_WRITE = "http://mcpo:8080/neo4j/write-cypher"
MCPO_READ  = "http://mcpo:8080/neo4j/read-cypher"
MCPO_SCHEMA = "http://mcpo:8080/neo4j/get-schema"

# ── 헬퍼 ──────────────────────────────────────────────────────────────────────
def uid(): return str(uuid.uuid4())

def workflow(name, nodes, connections, wid=None):
    return {
        "name": name,
        "nodes": nodes,
        "pinData": {},
        "connections": connections,
        "active": False,
        "settings": {"executionOrder": "v1", "binaryMode": "separate"},
        "versionId": uid(),
        "meta": {"instanceId": "ch5-practice"},
        "id": wid or uid()[:8].upper(),
        "tags": []
    }

def manual_trigger(pos):
    return {
        "parameters": {},
        "type": "n8n-nodes-base.manualTrigger",
        "typeVersion": 1,
        "position": pos,
        "id": uid(),
        "name": "When clicking 'Execute workflow'"
    }

def http_write(name, query, pos, always=True):
    n = {
        "parameters": {
            "method": "POST",
            "url": MCPO_WRITE,
            "sendBody": True,
            "bodyParameters": {"parameters": [{"name": "query", "value": query}]},
            "options": {}
        },
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.4,
        "position": pos,
        "id": uid(),
        "name": name
    }
    if always:
        n["alwaysOutputData"] = True
    return n

def http_write_dynamic(name, pos):
    """query 값을 {{ $json.query }} 로 동적으로 받는 HTTP Request 노드"""
    return {
        "parameters": {
            "method": "POST",
            "url": MCPO_WRITE,
            "sendBody": True,
            "bodyParameters": {"parameters": [{"name": "query", "value": "={{ $json.query }}"}]},
            "options": {}
        },
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.4,
        "position": pos,
        "id": uid(),
        "name": name,
        "alwaysOutputData": True
    }

def read_file(name, path, pos):
    return {
        "parameters": {"fileSelector": path, "options": {}},
        "type": "n8n-nodes-base.readWriteFile",
        "typeVersion": 1.1,
        "position": pos,
        "id": uid(),
        "name": name
    }

def parse_json(name, pos):
    return {
        "parameters": {"operation": "fromJson", "options": {}},
        "type": "n8n-nodes-base.extractFromFile",
        "typeVersion": 1.1,
        "position": pos,
        "id": uid(),
        "name": name
    }

def split_out(name, field, pos):
    return {
        "parameters": {"fieldToSplitOut": field, "options": {}},
        "type": "n8n-nodes-base.splitOut",
        "typeVersion": 1,
        "position": pos,
        "id": uid(),
        "name": name
    }

def split_batches(name, size, pos):
    return {
        "parameters": {"batchSize": size, "options": {}},
        "type": "n8n-nodes-base.splitInBatches",
        "typeVersion": 3,
        "position": pos,
        "id": uid(),
        "name": name
    }

def code_node(name, js, pos):
    return {
        "parameters": {"jsCode": js},
        "type": "n8n-nodes-base.code",
        "typeVersion": 2,
        "position": pos,
        "id": uid(),
        "name": name
    }

def aggregate_all(name, pos, destination_field=None):
    params = {"aggregate": "aggregateAllItemData", "options": {}}
    if destination_field:
        params["destinationFieldName"] = destination_field
    return {
        "parameters": params,
        "type": "n8n-nodes-base.aggregate",
        "typeVersion": 1,
        "position": pos,
        "id": uid(),
        "name": name
    }

def normalize_json_items_code():
    return r"""
const output = [];
for (const item of $input.all()) {
  const data = item.json;
  const records = Array.isArray(data) ? data : [data];
  for (const record of records) {
    output.push({ json: record });
  }
}
return output;
""".strip()

def sticky(content, w, h, pos, color=3):
    return {
        "parameters": {"content": content, "height": h, "width": w, "color": color},
        "type": "n8n-nodes-base.stickyNote",
        "typeVersion": 1,
        "position": pos,
        "id": uid(),
        "name": f"Note_{uid()[:4]}"
    }

def connect(src, dst, src_out=0, dst_in=0):
    """단방향 연결 엔트리 생성 (connections dict에 추가하는 형식)"""
    return {"node": dst, "type": "main", "index": dst_in}

def make_unwind_batch_code(row_expr, query_body, chunk_size, substring_limit=500):
    return f"""
const all = $input.all();
const out = [];
for (let offset = 0; offset < all.length; offset += {chunk_size}) {{
  const batch = all.slice(offset, offset + {chunk_size});
  const rows = batch.map(i => {{
    const r = i.json;
    const esc = s => String(s||'').replace(/\\\\/g,'\\\\\\\\').replace(/'/g,"\\\\'").substring(0,{substring_limit});
    return `{row_expr}`;
  }}).join(',');
  if (!rows) continue;
  out.push({{json: {{query:
`UNWIND [${{rows}}] AS row
{query_body}`
  }}}});
}}
return out;
""".strip()

def make_call_batch_code(call_expr, chunk_size):
    return f"""
const all = $input.all();
const out = [];
for (let offset = 0; offset < all.length; offset += {chunk_size}) {{
  const batch = all.slice(offset, offset + {chunk_size});
  const calls = batch.map(i => {{
    const r = i.json;
    const esc = s => String(s||'').replace(/\\\\/g,'\\\\\\\\').replace(/'/g,"\\\\'");
    return `{call_expr}`;
  }}).join('\\n');
  if (!calls) continue;
  out.push({{json: {{query: calls}}}});
}}
return out;
""".strip()

def build_connections(edges):
    """
    edges: [(src_name, dst_name, src_output_idx), ...]
    반환: n8n connections dict
    """
    conns = {}
    for (src, dst, out_idx) in edges:
        if src not in conns:
            conns[src] = {"main": []}
        # out_idx 번째 슬롯 확보
        while len(conns[src]["main"]) <= out_idx:
            conns[src]["main"].append([])
        conns[src]["main"][out_idx].append({"node": dst, "type": "main", "index": 0})
    return conns

# =============================================================================
# Workflow 00: Setup Constraints & Indexes
# =============================================================================
def gen_00():
    X0 = -464
    nodes = [manual_trigger([X0, 0])]

    constraints = [
        ("Technique.technique_id",  "CREATE CONSTRAINT technique_id_unique IF NOT EXISTS FOR (n:Technique) REQUIRE n.technique_id IS UNIQUE;"),
        ("Tactic.tactic_id",        "CREATE CONSTRAINT tactic_id_unique IF NOT EXISTS FOR (n:Tactic) REQUIRE n.tactic_id IS UNIQUE;"),
        ("ThreatActor.name",        "CREATE CONSTRAINT actor_name_unique IF NOT EXISTS FOR (n:ThreatActor) REQUIRE n.name IS UNIQUE;"),
        ("Malware.name",            "CREATE CONSTRAINT malware_name_unique IF NOT EXISTS FOR (n:Malware) REQUIRE n.name IS UNIQUE;"),
        ("Tool.name",               "CREATE CONSTRAINT tool_name_unique IF NOT EXISTS FOR (n:Tool) REQUIRE n.name IS UNIQUE;"),
        ("Mitigation.mid",          "CREATE CONSTRAINT mitigation_id_unique IF NOT EXISTS FOR (n:Mitigation) REQUIRE n.mitigation_id IS UNIQUE;"),
        ("Vulnerability.cve_id",    "CREATE CONSTRAINT cve_id_unique IF NOT EXISTS FOR (n:Vulnerability) REQUIRE n.cve_id IS UNIQUE;"),
        ("Indicator.value",         "CREATE CONSTRAINT indicator_value_unique IF NOT EXISTS FOR (n:Indicator) REQUIRE n.value IS UNIQUE;"),
        ("Incident.incident_id",    "CREATE CONSTRAINT incident_id_unique IF NOT EXISTS FOR (n:Incident) REQUIRE n.incident_id IS UNIQUE;"),
        ("Victim.org_name",         "CREATE CONSTRAINT victim_name_unique IF NOT EXISTS FOR (n:Victim) REQUIRE n.org_name IS UNIQUE;"),
    ]
    fulltext = [
        ("FT: Technique",      "CREATE FULLTEXT INDEX technique_ft IF NOT EXISTS FOR (n:Technique) ON EACH [n.name, n.description];"),
        ("FT: ThreatActor",    "CREATE FULLTEXT INDEX actor_ft IF NOT EXISTS FOR (n:ThreatActor) ON EACH [n.name];"),
        ("FT: Malware",        "CREATE FULLTEXT INDEX malware_ft IF NOT EXISTS FOR (n:Malware) ON EACH [n.name];"),
        ("FT: Vulnerability",  "CREATE FULLTEXT INDEX vuln_ft IF NOT EXISTS FOR (n:Vulnerability) ON EACH [n.cve_id, n.name, n.description];"),
        ("FT: Incident",       "CREATE FULLTEXT INDEX incident_ft IF NOT EXISTS FOR (n:Incident) ON EACH [n.title, n.summary];"),
    ]
    all_items = constraints + fulltext

    # 열 2개로 배치 (5개씩)
    for i, (name, query) in enumerate(all_items):
        col = i % 2
        row = i // 2
        x = -192 + col * 256
        y = -160 + row * 144
        nodes.append(http_write(name, query, [x, y]))

    # 연결: trigger → 첫 노드, 이후 직렬 체인
    edges = [("When clicking 'Execute workflow'", all_items[0][0], 0)]
    for i in range(len(all_items) - 1):
        edges.append((all_items[i][0], all_items[i+1][0], 0))

    return workflow("00 Setup Constraints & Indexes", nodes, build_connections(edges))

# =============================================================================
# Workflow 01: Load MITRE ATT&CK
# =============================================================================

# ── UNWIND 쿼리 생성 코드 (각 타입별) ────────────────────────────────────────

CODE_TACTICS = make_unwind_batch_code(
    "{tactic_id:'${esc(r.tactic_id)}',name:'${esc(r.name)}',shortname:'${esc(r.shortname)}',description:'${esc(r.description)}'}",
    "MERGE (t:Tactic {tactic_id: row.tactic_id})\nSET t.name = row.name, t.shortname = row.shortname, t.description = row.description",
    10
)

CODE_TECHNIQUES = make_unwind_batch_code(
    "{technique_id:'${esc(r.technique_id)}',name:'${esc(r.name)}',description:'${esc(r.description)}',is_sub:${!!r.is_subtechnique},platforms:'${esc((r.platforms||[]).join(','))}'}",
    "MERGE (t:Technique {technique_id: row.technique_id})\nSET t.name = row.name, t.description = row.description,\n    t.is_subtechnique = row.is_sub, t.platforms = row.platforms",
    50
)

CODE_ACTORS = make_unwind_batch_code(
    "{name:'${esc(r.name)}',aliases:'${esc((r.aliases||[]).join(','))}',description:'${esc(r.description)}'}",
    "MERGE (a:ThreatActor {name: row.name})\nSET a.aliases = row.aliases, a.description = row.description",
    50
)

CODE_MALWARE = make_unwind_batch_code(
    "{name:'${esc(r.name)}',malware_type:'${esc(r.malware_type)}',description:'${esc(r.description)}'}",
    "MERGE (m:Malware {name: row.name})\nSET m.malware_type = row.malware_type, m.description = row.description",
    50
)

CODE_TOOLS = make_unwind_batch_code(
    "{name:'${esc(r.name)}',tool_type:'${esc(r.tool_type)}',description:'${esc(r.description)}'}",
    "MERGE (t:Tool {name: row.name})\nSET t.tool_type = row.tool_type, t.description = row.description",
    50
)

CODE_MITIGATIONS = make_unwind_batch_code(
    "{mitigation_id:'${esc(r.mitigation_id)}',name:'${esc(r.name)}',description:'${esc(r.description)}'}",
    "MERGE (m:Mitigation {mitigation_id: row.mitigation_id})\nSET m.name = row.name, m.description = row.description",
    50
)

CODE_RELATIONSHIPS = make_call_batch_code(
    "CALL { OPTIONAL MATCH (s:${r.src_label} {${r.src_key}: '${esc(r.src_val)}'}) OPTIONAL MATCH (d:${r.dst_label} {${r.dst_key}: '${esc(r.dst_val)}'}) WITH s,d WHERE s IS NOT NULL AND d IS NOT NULL MERGE (s)-[:${r.neo4j_rel}]->(d) }",
    50
)


def gen_01():
    """
    구조: Trigger → [Tactics] → [Techniques] → [Actors] → [Malware] → [Tools] → [Mitigations] → [Relationships]
    각 그룹: Read → Parse → Code(전체 입력을 배치 query item들로 생성) → HTTP(item별 실행) → Aggregate(완료 수집)
    """
    BASE = "/home/node/.n8n-files"

    groups = [
        ("Tactics",       f"{BASE}/mitre/tactics.json",       CODE_TACTICS),
        ("Techniques",    f"{BASE}/mitre/techniques.json",    CODE_TECHNIQUES),
        ("Actors",        f"{BASE}/mitre/threat_actors.json", CODE_ACTORS),
        ("Malware",       f"{BASE}/mitre/malware.json",       CODE_MALWARE),
        ("Tools",         f"{BASE}/mitre/tools.json",         CODE_TOOLS),
        ("Mitigations",   f"{BASE}/mitre/mitigations.json",   CODE_MITIGATIONS),
        ("Relationships", f"{BASE}/mitre/relationships.json", CODE_RELATIONSHIPS),
    ]

    nodes   = []
    edges   = []
    trigger = manual_trigger([-464, 400])
    nodes.append(trigger)

    prev_done_src = "When clicking 'Execute workflow'"

    for gi, (label, fpath, code) in enumerate(groups):
        x_base = gi * 1200
        y      = 400

        r_node  = read_file(  f"Read {label}",   fpath,     [x_base + 0,   y])
        p_node  = parse_json( f"Parse {label}",             [x_base + 220, y])
        n_node  = code_node(  f"Normalize {label}", normalize_json_items_code(), [x_base + 440, y])
        c_node  = code_node(  f"Build {label} Queries", code, [x_base + 660, y])
        h_node  = http_write_dynamic(f"MERGE {label}",      [x_base + 880, y])
        a_node  = aggregate_all(f"Done {label}",            [x_base + 1100, y])

        nodes += [r_node, p_node, n_node, c_node, h_node, a_node]

        edges.append((prev_done_src, f"Read {label}", 0))
        edges.append((f"Read {label}",   f"Parse {label}",          0))
        edges.append((f"Parse {label}",  f"Normalize {label}",      0))
        edges.append((f"Normalize {label}", f"Build {label} Queries", 0))
        edges.append((f"Build {label} Queries", f"MERGE {label}",   0))
        edges.append((f"MERGE {label}",  f"Done {label}",           0))

        prev_done_src = f"Done {label}"

    return workflow("01 Load MITRE ATT&CK", nodes, build_connections(edges))

# =============================================================================
# Workflow 02: Load CISA KEV
# =============================================================================

CODE_KEV = make_unwind_batch_code(
    "{cve_id:'${esc(r.cve_id)}',name:'${esc(r.name)}',vendor:'${esc(r.vendor)}',product:'${esc(r.product)}',description:'${esc(r.description)}',date_added:'${esc(r.date_added)}',ransomware_use:'${esc(r.ransomware_use)}'}",
    "MERGE (v:Vulnerability {cve_id: row.cve_id})\nSET v.name = row.name, v.vendor = row.vendor, v.product = row.product,\n    v.description = row.description, v.date_added = row.date_added,\n    v.ransomware_use = row.ransomware_use",
    100
)

def gen_02():
    BASE  = "/home/node/.n8n-files"
    fpath = f"{BASE}/kev/vulnerabilities.json"
    nodes, edges = [], []

    trig  = manual_trigger([-464, 200])
    r_nd  = read_file("Read KEV",   fpath,        [-200, 200])
    p_nd  = parse_json("Parse KEV",               [  20, 200])
    s_nd  = split_out("Split Out KEV", "data",   [240, 200])
    n_nd  = code_node("Normalize KEV", normalize_json_items_code(), [460, 200])
    c_nd  = code_node("Build KEV Queries", CODE_KEV,[ 680, 200])
    h_nd  = http_write_dynamic("MERGE Vulnerability", [900, 200])

    nodes = [trig, r_nd, p_nd, s_nd, n_nd, c_nd, h_nd]
    edges = [
        ("When clicking 'Execute workflow'", "Read KEV",          0),
        ("Read KEV",   "Parse KEV",          0),
        ("Parse KEV",  "Split Out KEV",      0),
        ("Split Out KEV", "Normalize KEV",   0),
        ("Normalize KEV", "Build KEV Queries", 0),
        ("Build KEV Queries", "MERGE Vulnerability", 0),
    ]
    return workflow("02 Load CISA KEV", nodes, build_connections(edges))

# =============================================================================
# Workflow 03: Load URLhaus
# =============================================================================

CODE_URLHAUS_BATCH = r"""
const esc = s => String(s || '').replace(/\\/g,'\\\\').replace(/'/g,"\\'");
const calls = [];
for (const item of $input.all()) {
  const r = item.json;
  const url = esc(r.value);
  calls.push(`CALL {
  MERGE (i:Indicator {value:'${url}'})
  SET i.indicator_type='${esc(r.indicator_type)}', i.status='${esc(r.status)}',
      i.threat='${esc(r.threat)}', i.date_added='${esc(r.date_added)}'
}`);
  if (r.host && r.host_type) {
    const hostLabel = r.host_type === 'ip' ? 'IPAddress' : 'Domain';
    const hostKey = r.host_type === 'ip' ? 'ip' : 'domain';
    calls.push(`CALL {
  MATCH (i:Indicator {value:'${url}'})
  MERGE (h:${hostLabel} {${hostKey}:'${esc(r.host)}'})
  MERGE (i)-[:HOSTED_ON]->(h)
}`);
  }
  for (const cve of (r.cve_ids || [])) {
    calls.push(`CALL {
  MATCH (i:Indicator {value:'${url}'})
  OPTIONAL MATCH (v:Vulnerability {cve_id:'${esc(cve)}'})
  WITH i, v
  WHERE v IS NOT NULL
  MERGE (i)-[:EXPLOITS]->(v)
}`);
  }
  if (r.malware_name) {
    calls.push(`CALL {
  MATCH (i:Indicator {value:'${url}'})
  MERGE (m:Malware {name:'${esc(r.malware_name)}'})
  MERGE (i)-[:INDICATES]->(m)
}`);
  }
}
if (calls.length === 0) return [];
return [{json:{query: calls.join('\n')}}];
""".strip()

def gen_03():
    BASE  = "/home/node/.n8n-files"
    fpath = f"{BASE}/urlhaus/indicators.json"
    nodes, edges = [], []

    trig   = manual_trigger([-464, 400])
    r_nd   = read_file("Read URLhaus",    fpath,             [-200, 400])
    p_nd   = parse_json("Parse URLhaus",                     [  20, 400])
    s_nd   = split_out("Split Out URLhaus", "data",          [240, 400])
    n_nd   = code_node("Normalize URLhaus", normalize_json_items_code(), [460, 400])
    b_nd   = split_batches("Split URLhaus", 100,             [ 680, 400])
    c_nd   = code_node("Build URLhaus Batch Query", CODE_URLHAUS_BATCH, [900, 400])
    h_nd   = http_write_dynamic("MERGE URLhaus Batch", [1120, 400])

    nodes = [trig, r_nd, p_nd, s_nd, n_nd, b_nd, c_nd, h_nd]
    edges = [
        ("When clicking 'Execute workflow'", "Read URLhaus", 0),
        ("Read URLhaus",   "Parse URLhaus",  0),
        ("Parse URLhaus",  "Split Out URLhaus",  0),
        ("Split Out URLhaus", "Normalize URLhaus", 0),
        ("Normalize URLhaus", "Split URLhaus", 0),
        ("Split URLhaus",  "Build URLhaus Batch Query", 0),
        ("Build URLhaus Batch Query", "MERGE URLhaus Batch", 0),
        ("MERGE URLhaus Batch", "Split URLhaus", 0),
    ]
    return workflow("03 Load URLhaus", nodes, build_connections(edges))

# =============================================================================
# Workflow 04: Load Incidents + 교차 연결
# =============================================================================

CODE_INCIDENT_VICTIM = r"""
const batch = $input.all();
const calls = batch.map(i => {
  const r = i.json;
  const esc = s => String(s||'').replace(/\\/g,'\\\\').replace(/'/g,"\\'").substring(0,500);
  const iid = esc(r.incident_id), title = esc(r.title), ts = esc(r.timestamp), summary = esc(r.summary);
  const org = esc(r.org_name), sys = esc(r.system), ind = esc(r.industry), cty = esc(r.country);
  return `CALL {
  MERGE (inc:Incident {incident_id:'${iid}'})
  SET inc.title='${title}', inc.timestamp='${ts}', inc.summary='${summary}'
  MERGE (vic:Victim {org_name:'${org}'})
  SET vic.system='${sys}', vic.industry='${ind}', vic.country='${cty}'
  MERGE (inc)-[:TARGETED]->(vic)
}`;
}).join('\n');
return [{json:{query: calls}}];
""".strip()

CODE_INCIDENT_ACTOR = r"""
const batch = $input.all().filter(i => i.json.threat_actor);
if (batch.length === 0) return [];
const calls = batch.map(i => {
  const r = i.json;
  const esc = s => String(s||'').replace(/\\/g,'\\\\').replace(/'/g,"\\'");
  const iid = esc(r.incident_id), actor = esc(r.threat_actor), conf = esc(r.confidence||'');
  return `CALL { MATCH (inc:Incident {incident_id:'${iid}'}) MERGE (a:ThreatActor {name:'${actor}'}) MERGE (inc)-[r:ATTRIBUTED_TO]->(a) SET r.confidence='${conf}' }`;
}).join('\n');
return [{json:{query: calls}}];
""".strip()

CODE_INCIDENTS_BATCH = r"""
const esc = s => String(s || '').replace(/\\/g,'\\\\').replace(/'/g,"\\'");
const calls = [];
for (const item of $input.all()) {
  const inc = item.json;
  const iid = esc(inc.incident_id);
  calls.push(`CALL {
  MERGE (inc:Incident {incident_id:'${iid}'})
  SET inc.title='${esc(inc.title)}', inc.timestamp='${esc(inc.timestamp)}', inc.summary='${esc(inc.summary)}'
  MERGE (vic:Victim {org_name:'${esc(inc.org_name)}'})
  SET vic.system='${esc(inc.system)}', vic.industry='${esc(inc.industry)}', vic.country='${esc(inc.country)}'
  MERGE (inc)-[:TARGETED]->(vic)
}`);
  if (inc.threat_actor) {
    calls.push(`CALL {
  MATCH (inc:Incident {incident_id:'${iid}'})
  MERGE (a:ThreatActor {name:'${esc(inc.threat_actor)}'})
  MERGE (inc)-[r:ATTRIBUTED_TO]->(a)
  SET r.confidence='${esc(inc.confidence || '')}'
}`);
  }
  for (const step of (inc.attack_flow || [])) {
    const techniqueId = esc(step.technique_id || '');
    const techniqueName = esc(step.technique_name || '');
    const phase = esc(step.phase || '');
    const outcome = esc(step.outcome || '');
    if (techniqueId) {
      calls.push(`CALL {
  MATCH (inc:Incident {incident_id:'${iid}'})
  MERGE (t:Technique {technique_id:'${techniqueId}'})
  SET t.name = coalesce(t.name, '${techniqueName}')
  MERGE (inc)-[:USES_TECHNIQUE {phase:'${phase}',outcome:'${outcome}'}]->(t)
}`);
    }
    const rel = step.related_entity || {};
    const rtype = rel.type || '';
    const rval = esc(rel.value || '');
    if (rtype === 'Vulnerability' && rval.startsWith('CVE')) {
      calls.push(`CALL {
  MATCH (inc:Incident {incident_id:'${iid}'})
  MERGE (v:Vulnerability {cve_id:'${rval}'})
  MERGE (inc)-[:EXPLOITED]->(v)
}`);
    } else if (rtype === 'Malware' && rval) {
      calls.push(`CALL {
  MATCH (inc:Incident {incident_id:'${iid}'})
  MERGE (m:Malware {name:'${rval}'})
  MERGE (inc)-[:INVOLVES_MALWARE]->(m)
}`);
    } else if (rtype === 'Indicator' && rval) {
      calls.push(`CALL {
  MATCH (inc:Incident {incident_id:'${iid}'})
  MERGE (ind:Indicator {value:'${rval}'})
  MERGE (inc)-[:INVOLVES_INDICATOR]->(ind)
}`);
    } else if (rtype === 'Threat Group' && rval) {
      calls.push(`CALL {
  MATCH (inc:Incident {incident_id:'${iid}'})
  MERGE (a:ThreatActor {name:'${rval}'})
  MERGE (inc)-[:ATTRIBUTED_TO]->(a)
}`);
    }
  }
}
if (calls.length === 0) return [];
return [{json:{query: calls.join('\n')}}];
""".strip()

def gen_04():
    BASE  = "/home/node/.n8n-files"
    fpath = f"{BASE}/incidents/incidents.json"
    nodes, edges = [], []

    trig    = manual_trigger([-464, 600])
    r_nd    = read_file("Read Incidents",   fpath,             [-200, 600])
    p_nd    = parse_json("Parse Incidents",                     [  20, 600])
    s_nd    = split_out("Split Out Incidents", "data",        [240, 600])
    n_nd    = code_node("Normalize Incidents", normalize_json_items_code(), [460, 600])
    b_nd    = split_batches("Split Incidents", 20,             [ 680, 600])

    c_nd    = code_node("Build Incidents Batch Query", CODE_INCIDENTS_BATCH, [920, 600])
    h_nd    = http_write_dynamic("MERGE Incidents Batch", [1140, 600])

    nodes = [trig, r_nd, p_nd, s_nd, n_nd, b_nd, c_nd, h_nd]
    edges = [
        ("When clicking 'Execute workflow'", "Read Incidents", 0),
        ("Read Incidents",   "Parse Incidents", 0),
        ("Parse Incidents",  "Split Out Incidents", 0),
        ("Split Out Incidents", "Normalize Incidents", 0),
        ("Normalize Incidents", "Split Incidents", 0),
        ("Split Incidents", "Build Incidents Batch Query", 0),
        ("Build Incidents Batch Query", "MERGE Incidents Batch", 0),
        ("MERGE Incidents Batch", "Split Incidents", 0),
    ]
    return workflow("04 Load Incidents", nodes, build_connections(edges))

# =============================================================================
# Workflow 05: Text2Cypher Chatbot
# (ch4의 00_explore_neo4j.json 구조를 ch5 스키마에 맞게 재구성)
# =============================================================================

SYSTEM_PROMPT = """You are a security knowledge graph analyst. You translate natural language questions into Cypher queries for a Neo4j graph containing:

**Node Labels & Primary Keys:**
- Technique (technique_id: T-code)
- Tactic (tactic_id: TA-code)
- ThreatActor (name)
- Malware (name)
- Tool (name)
- Mitigation (mitigation_id: M-code)
- Vulnerability (cve_id: CVE-XXXX-XXXXX)
- Indicator (value: URL)
- Incident (incident_id)
- Victim (org_name)
- IPAddress (ip), Domain (domain)

**Relationships:**
- (Technique)-[:BELONGS_TO]->(Tactic)
- (Technique)-[:SUBTECHNIQUE_OF]->(Technique)
- (ThreatActor)-[:USES_TECHNIQUE]->(Technique)
- (ThreatActor)-[:USES_MALWARE]->(Malware)
- (ThreatActor)-[:USES_TOOL]->(Tool)
- (Malware)-[:USES_TECHNIQUE]->(Technique)
- (Mitigation)-[:MITIGATES]->(Technique)
- (Indicator)-[:HOSTED_ON]->(IPAddress|Domain)
- (Indicator)-[:EXPLOITS]->(Vulnerability)
- (Indicator)-[:INDICATES]->(Malware)
- (Incident)-[:TARGETED]->(Victim)
- (Incident)-[:ATTRIBUTED_TO]->(ThreatActor)
- (Incident)-[:USES_TECHNIQUE]->(Technique)
- (Incident)-[:EXPLOITED]->(Vulnerability)
- (Incident)-[:INVOLVES_MALWARE]->(Malware)
- (Incident)-[:INVOLVES_INDICATOR]->(Indicator)

**Runtime Input:**
- User request: {{ $json.chatInput }}
- Current schema: {{ $json.schema }}

**Rules:**
1. Always use read-cypher tool at least once before answering.
2. Never guess — base answers on actual query results.
3. Use LIMIT for open-ended queries (unless user asks for all).
4. Answer in Korean.
5. Show the Cypher query used at the beginning of your answer.
6. Use FULLTEXT search for keyword queries: CALL db.index.fulltext.queryNodes('technique_ft', $keyword) YIELD node"""

def gen_05():
    nodes, edges = [], []

    chat_trig = {
        "parameters": {"options": {}},
        "type": "@n8n/n8n-nodes-langchain.chatTrigger",
        "typeVersion": 1.4,
        "position": [0, 0],
        "id": uid(),
        "name": "When chat message received",
        "webhookId": uid()
    }

    schema_req = {
        "parameters": {
            "method": "POST",
            "url": MCPO_SCHEMA,
            "sendBody": True,
            "specifyBody": "json",
            "jsonBody": '{"properties": {}}',
            "options": {}
        },
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.2,
        "position": [208, 128],
        "id": uid(),
        "name": "Get Schema"
    }

    agg_schema = {
        "parameters": {
            "aggregate": "aggregateAllItemData",
            "destinationFieldName": "schema",
            "options": {}
        },
        "type": "n8n-nodes-base.aggregate",
        "typeVersion": 1,
        "position": [432, 128],
        "id": uid(),
        "name": "Aggregate Schema"
    }

    merge_nd = {
        "parameters": {},
        "type": "n8n-nodes-base.merge",
        "typeVersion": 3.2,
        "position": [656, 0],
        "id": uid(),
        "name": "Merge"
    }

    agg_all = {
        "parameters": {"aggregate": "aggregateAllItemData", "options": {}},
        "type": "n8n-nodes-base.aggregate",
        "typeVersion": 1,
        "position": [880, 0],
        "id": uid(),
        "name": "Aggregate All"
    }

    set_ctx = {
        "parameters": {
            "assignments": {"assignments": [
                {"id": uid(), "name": "chatInput", "value": "={{ $json.data[0].chatInput }}", "type": "string"},
                {"id": uid(), "name": "sessionId", "value": "={{ $json.data[0].sessionId }}", "type": "string"},
                {"id": uid(), "name": "schema",    "value": "={{ $json.data[1].schema }}",    "type": "string"},
            ]},
            "options": {}
        },
        "type": "n8n-nodes-base.set",
        "typeVersion": 3.4,
        "position": [1104, 0],
        "id": uid(),
        "name": "Set Context"
    }

    llm_node = {
        "parameters": {
            "model": {"__rl": True, "value": "qwen3.5-35b", "mode": "id"},
            "options": {}
        },
        "type": "@n8n/n8n-nodes-langchain.lmChatOpenAi",
        "typeVersion": 1.2,
        "position": [1552, 224],
        "id": uid(),
        "name": "vLLM Model",
        "credentials": {"openAiApi": {"id": "GAnv0w5e7r45WGtw", "name": "OpenAI account"}}
    }

    memory_node = {
        "parameters": {},
        "type": "@n8n/n8n-nodes-langchain.memoryBufferWindow",
        "typeVersion": 1.3,
        "position": [1680, 224],
        "id": uid(),
        "name": "Simple Memory"
    }

    agent_node = {
        "parameters": {
            "promptType": "define",
            "text": "={{ $json.chatInput }}",
            "options": {"systemMessage": f"={SYSTEM_PROMPT}"}
        },
        "type": "@n8n/n8n-nodes-langchain.agent",
        "typeVersion": 1.7,
        "position": [1328, 0],
        "id": uid(),
        "name": "AI Agent"
    }

    read_tool = {
        "parameters": {
            "toolDescription": "Execute a read-only Cypher query on the Neo4j security knowledge graph",
            "method": "POST",
            "url": MCPO_READ,
            "sendBody": True,
            "bodyParameters": {"parameters": [
                {"name": "query", "value": "={{ /*n8n-auto-generated-fromAI-override*/ $fromAI('parameters0_Value', ``, 'string') }}"}
            ]},
            "options": {}
        },
        "type": "n8n-nodes-base.httpRequestTool",
        "typeVersion": 4.4,
        "position": [1808, 224],
        "id": uid(),
        "name": "read-cypher"
    }

    nodes = [chat_trig, schema_req, agg_schema, merge_nd, agg_all,
             set_ctx, llm_node, memory_node, agent_node, read_tool]

    conns = {
        "When chat message received": {"main": [
            [{"node": "Get Schema",  "type": "main", "index": 0},
             {"node": "Merge",       "type": "main", "index": 0}]
        ]},
        "Get Schema":        {"main": [[{"node": "Aggregate Schema", "type": "main", "index": 0}]]},
        "Aggregate Schema":  {"main": [[{"node": "Merge",            "type": "main", "index": 1}]]},
        "Merge":             {"main": [[{"node": "Aggregate All",    "type": "main", "index": 0}]]},
        "Aggregate All":     {"main": [[{"node": "Set Context",      "type": "main", "index": 0}]]},
        "Set Context":       {"main": [[{"node": "AI Agent",         "type": "main", "index": 0}]]},
        "vLLM Model":        {"ai_languageModel": [[{"node": "AI Agent", "type": "ai_languageModel", "index": 0}]]},
        "Simple Memory":     {"ai_memory":        [[{"node": "AI Agent", "type": "ai_memory",        "index": 0}]]},
        "read-cypher":       {"ai_tool":          [[{"node": "AI Agent", "type": "ai_tool",          "index": 0}]]},
    }

    return {"name": "05 Text2Cypher Chatbot",
            "nodes": nodes, "pinData": {}, "connections": conns,
            "active": False, "settings": {"executionOrder": "v1"},
            "versionId": uid(), "meta": {"instanceId": "ch5-practice"},
            "id": uid()[:8].upper(), "tags": []}

# =============================================================================
# 생성 및 저장
# =============================================================================
generators = [
    ("00_setup_constraints.json", gen_00),
    ("01_load_mitre.json",        gen_01),
    ("02_load_kev.json",          gen_02),
    ("03_load_urlhaus.json",      gen_03),
    ("04_load_incidents.json",    gen_04),
    ("05_text2cypher_chatbot.json", gen_05),
]

for fname, gen_fn in generators:
    data = gen_fn()
    out_path = os.path.join(OUT_DIR, fname)
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    node_count = len(data['nodes'])
    print(f"  {fname:<35} {node_count:>3} nodes")

print(f"\n완료! {len(generators)}개 워크플로우 생성 → {OUT_DIR}")
