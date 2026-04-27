(function () {
  const API_CANDIDATES = window.GRAPH_VIEWER_API_URL
    ? [window.GRAPH_VIEWER_API_URL]
    : [
        `${window.location.protocol}//${window.location.hostname}:5678/webhook/graph-viewer-api`,
        `${window.location.protocol}//${window.location.hostname}:5678/webhook-test/graph-viewer-api`,
      ];
  const incidentListEl = document.getElementById("incident-list");
  const incidentSearchEl = document.getElementById("incident-search");
  const fetchIncidentsBtn = document.getElementById("fetch-incidents");
  const refreshIncidentsBtn = document.getElementById("refresh-incidents");
  const selectedIncidentTitleEl = document.getElementById("selected-incident-title");
  const nodeDetailsEl = document.getElementById("node-details");
  const expandControlsEl = document.getElementById("expand-controls");
  const graphStatsEl = document.getElementById("graph-stats");
  const statusLogEl = document.getElementById("status-log");
  const fitGraphBtn = document.getElementById("fit-graph");
  const resetGraphBtn = document.getElementById("reset-graph");
  const nodes = new vis.DataSet([]);
  const edges = new vis.DataSet([]);
  const network = new vis.Network(document.getElementById("graph-canvas"), { nodes, edges }, { autoResize: true, layout: { improvedLayout: true }, physics: { stabilization: { iterations: 240 }, barnesHut: { gravitationalConstant: -4600, springLength: 150, springConstant: 0.04, damping: 0.18 } }, interaction: { hover: true, navigationButtons: true }, nodes: { shape: "dot", size: 20, font: { size: 14, face: "Arial", color: "#102033", strokeWidth: 3, strokeColor: "#ffffff" }, borderWidth: 2 }, edges: { arrows: { to: { enabled: false } }, color: { color: "#9ab0c3", highlight: "#0b5cab" }, width: 1.5, smooth: { type: "dynamic" }, font: { size: 11, color: "#607489", strokeWidth: 3, strokeColor: "#ffffff", align: "middle" } } });
  const state = { incidents: [], filteredIncidents: [], selectedIncidentId: "", selectedNodeId: "", apiUrl: API_CANDIDATES[0], incidentsLoaded: false };
  const labelColors = { Incident: { background: "#17345a", border: "#0b5cab", font: { color: "#ffffff" }, size: 28 }, ThreatActor: { background: "#7a1f1f", border: "#a61f1f", font: { color: "#ffffff" }, size: 24 }, Victim: { background: "#0f766e", border: "#0f766e", font: { color: "#ffffff" }, size: 24 }, Technique: { background: "#eef6ff", border: "#0b5cab" }, Malware: { background: "#fff2f2", border: "#ca3131" }, Vulnerability: { background: "#fff9eb", border: "#d29c1d" }, Indicator: { background: "#f2f7ff", border: "#4b77b8" }, IPAddress: { background: "#f4f1ff", border: "#7058c6" }, Domain: { background: "#eefaf6", border: "#1e8a5a" }, Tool: { background: "#f8f7f3", border: "#7a6a49" } };
  const log = (message) => { statusLogEl.textContent = message; };
  const setGraphStats = () => { graphStatsEl.textContent = `노드 ${nodes.length}개 · 링크 ${edges.length}개`; };
  async function api(action, payload = {}) {
    let lastError = null;
    for (const url of [state.apiUrl, ...API_CANDIDATES.filter((candidate) => candidate !== state.apiUrl)]) {
      try {
        const response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action, ...payload }) });
        if (!response.ok) throw new Error(`status ${response.status}`);
        state.apiUrl = url;
        return response.json();
      } catch (error) {
        lastError = error;
      }
    }
    throw new Error(`API ${action} failed: ${lastError?.message || "unknown error"}`);
  }
  const normalizeNode = (node) => Object.assign({ id: node.id, label: node.name, title: `${node.label}<br/>${node.name}`, group: node.label }, labelColors[node.label] || {});
  const normalizeEdge = (link) => ({ id: `${link.source}|${link.target}|${link.label}`, from: link.source, to: link.target, label: link.label, title: link.label });
  function renderIncidents() {
    incidentListEl.innerHTML = "";
    if (!state.incidentsLoaded) {
      incidentListEl.innerHTML = `<div class="detail-card muted">Fetch Incidents를 눌러 사건 목록을 불러오세요.</div>`;
      return;
    }
    if (!state.filteredIncidents.length) {
      incidentListEl.innerHTML = `<div class="detail-card muted">조건에 맞는 Incident가 없습니다.</div>`;
      return;
    }
    state.filteredIncidents.forEach((incident) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = `incident-item ${state.selectedIncidentId === incident.incidentId ? "active" : ""}`;
      item.innerHTML = `<h3>${incident.title}</h3><div class="incident-meta">${incident.incidentId}${incident.timestamp ? ` · ${incident.timestamp}` : ""}</div><p class="incident-summary">${incident.summary || "요약 정보 없음"}</p>`;
      item.addEventListener("click", () => loadIncidentGraph(incident));
      incidentListEl.appendChild(item);
    });
  }
  function filterIncidents() {
    if (!state.incidentsLoaded) return;
    const keyword = incidentSearchEl.value.trim().toLowerCase();
    state.filteredIncidents = state.incidents.filter((incident) => !keyword || incident.title.toLowerCase().includes(keyword) || incident.incidentId.toLowerCase().includes(keyword) || incident.summary.toLowerCase().includes(keyword));
    renderIncidents();
  }
  function resetDetails() { nodeDetailsEl.className = "detail-card muted"; nodeDetailsEl.innerHTML = "그래프에서 노드를 선택하면 세부정보가 표시됩니다."; expandControlsEl.className = "detail-card muted"; expandControlsEl.innerHTML = "확장 가능한 라벨을 확인하려면 노드를 선택하세요."; }
  function renderNodeDetails(node) { if (!node) return resetDetails(); const properties = Object.entries(node.properties || {}).slice(0, 20).map(([key, value]) => `<div class="property-item"><span class="property-key">${key}</span><span class="property-value">${String(value)}</span></div>`).join(""); const neighbors = (node.neighbors || []).filter((neighbor) => neighbor && neighbor.id).map((neighbor) => `<span class="pill">${(neighbor.labels || [])[0] || "Node"} · ${neighbor.label || neighbor.id}</span>`).join(" "); nodeDetailsEl.className = "detail-card"; nodeDetailsEl.innerHTML = `<p class="eyebrow">${node.label}</p><h3>${node.name}</h3><div class="property-grid">${properties || '<div class="property-item"><span class="property-value">표시 가능한 속성이 없습니다.</span></div>'}</div><div style="margin-top:16px;"><h4>Connected Preview</h4><div style="display:flex;flex-wrap:wrap;gap:8px;">${neighbors || '<span class="hint">미리보기 없음</span>'}</div></div>`; }
  function renderExpandControls(node, counts) { if (!node) return resetDetails(); if (!counts.length) { expandControlsEl.className = "detail-card"; expandControlsEl.innerHTML = `<p class="hint">확장 가능한 새 이웃 노드가 없습니다.</p>`; return; } const optionsHtml = counts.map((item) => `<div class="neighbor-option"><label><input type="checkbox" value="${item.label}" checked /><span>${item.label}</span></label><span class="pill">${item.count}</span></div>`).join(""); expandControlsEl.className = "detail-card"; expandControlsEl.innerHTML = `<p class="hint">선택한 라벨의 인접 노드를 현재 그래프에 추가합니다.</p><div class="neighbor-options">${optionsHtml}</div><div style="display:flex;gap:10px;margin-top:14px;"><button id="expand-selected" class="button button-primary">선택 라벨 확장</button></div>`; document.getElementById("expand-selected").addEventListener("click", async () => { const selectedLabels = [...expandControlsEl.querySelectorAll("input[type=checkbox]:checked")].map((checkbox) => checkbox.value); if (!selectedLabels.length) return log("확장할 라벨을 하나 이상 선택하세요."); log(`${node.name} 기준으로 ${selectedLabels.join(", ")} 확장 중...`); try { const response = await api("expand_node", { nodeId: node.id, targetLabels: selectedLabels, existingNodeIds: nodes.getIds() }); mergeGraph(response.expansion || { nodes: [], links: [] }); log(`확장 완료: 새 노드 ${(response.expansion?.nodes || []).length}개`); } catch (error) { log(`확장 실패: ${error.message}`); } }); }
  function mergeGraph(graph) { (graph.nodes || []).forEach((node) => { if (!nodes.get(node.id)) nodes.add(normalizeNode(node)); }); (graph.links || []).forEach((link) => { const edge = normalizeEdge(link); if (!edges.get(edge.id)) edges.add(edge); }); setGraphStats(); network.stabilize(120); }
  async function loadIncidents() {
    log("Incident 목록을 불러오는 중...");
    const response = await api("incidents");
    state.incidents = response.incidents || [];
    state.filteredIncidents = [...state.incidents];
    state.incidentsLoaded = true;
    renderIncidents();
    log(`Incident ${state.incidents.length}건 로드 완료 · endpoint: ${state.apiUrl}`);
  }
  async function loadIncidentGraph(incident) { state.selectedIncidentId = incident.incidentId; selectedIncidentTitleEl.textContent = incident.title; resetDetails(); renderIncidents(); log(`${incident.incidentId} 그래프 로드 중...`); try { const response = await api("incident_graph", { incidentId: incident.incidentId }); nodes.clear(); edges.clear(); mergeGraph(response.graph || { nodes: [], links: [] }); network.fit({ animation: true }); log(`그래프 로드 완료: 노드 ${nodes.length}개`); } catch (error) { log(`그래프 로드 실패: ${error.message}`); } }
  async function handleNodeSelect(nodeId) { state.selectedNodeId = nodeId; const basicNode = nodes.get(nodeId); if (!basicNode) return; log(`${basicNode.group || "Node"} 선택: ${basicNode.label}`); try { const [detailsResponse, countsResponse] = await Promise.all([api("node_details", { nodeId }), api("neighbor_counts", { nodeId, existingNodeIds: nodes.getIds() })]); renderNodeDetails(detailsResponse.node); renderExpandControls(detailsResponse.node, countsResponse.neighborCounts || []); } catch (error) { log(`노드 정보 조회 실패: ${error.message}`); } }
  network.on("click", (params) => { if (params.nodes.length) handleNodeSelect(params.nodes[0]); });
  fitGraphBtn.addEventListener("click", () => network.fit({ animation: true }));
  resetGraphBtn.addEventListener("click", () => { if (!state.selectedIncidentId) return; const incident = state.incidents.find((item) => item.incidentId === state.selectedIncidentId); if (incident) loadIncidentGraph(incident); });
  incidentSearchEl.addEventListener("input", filterIncidents);
  fetchIncidentsBtn.addEventListener("click", () => loadIncidents().catch((error) => log(error.message)));
  refreshIncidentsBtn.addEventListener("click", () => loadIncidents().catch((error) => log(error.message)));
  renderIncidents();
  log(`대기 중 · 기본 endpoint 후보: ${API_CANDIDATES.join(" , ")}`);
})();
