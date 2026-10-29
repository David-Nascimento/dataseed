(function () {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);

  const form = $("#form");
  const els = {
    reqUrl: $("#reqUrl"),
    viewport: $("#viewport"),
    output: $("#output"),
    tableWrap: $("#tableWrap"),
    errorBox: $("#errorBox"),
    errorTitle: $("#errorTitle"),
    errorText: $("#errorText"),
    meta: $("#meta"),
    metaCount: $("#metaCount"),
    metaSize: $("#metaSize"),
    metaTime: $("#metaTime"),
    tabJson: $("#tabJson"),
    tabTable: $("#tabTable"),
    btnGenerate: $("#btnGenerate"),
    btnCopy: $("#btnCopy"),
    btnDownload: $("#btnDownload"),
    downloadLabel: $("#downloadLabel"),
    count: $("#count"),
    seed: $("#seed"),
    apiBase: $("#apiBase"),
    health: $("#health"),
    healthText: $("#healthText"),
    toast: $("#toast"),
    docs: $("#docs"),
  };

  const state = {
    view: "json",       // "json" | "table"
    busy: false,
    maxCount: 100,
    last: null,         // { text, format, segment, data, count }
  };

  /* ---------------- utilidades ---------------- */

  function store(key, value) {
    try {
      if (value === undefined) return localStorage.getItem(key);
      localStorage.setItem(key, value);
    } catch (_) { /* armazenamento indisponível: segue sem persistir */ }
    return null;
  }

  function baseUrl() {
    const typed = (els.apiBase.value || "").trim().replace(/\/+$/, "");
    return typed || window.location.origin;
  }

  function formatBytes(n) {
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1).replace(".", ",")} KB`;
    return `${(n / 1024 / 1024).toFixed(1).replace(".", ",")} MB`;
  }

  function plural(n, one, many) {
    return `${n.toLocaleString("pt-BR")} ${n === 1 ? one : many}`;
  }

  let toastTimer;
  function toast(message) {
    els.toast.textContent = message;
    els.toast.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { els.toast.hidden = true; }, 2200);
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (_) {
      // Fallback para páginas fora de HTTPS/localhost
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      let ok = false;
      try { ok = document.execCommand("copy"); } catch (_) { ok = false; }
      ta.remove();
      return ok;
    }
  }

  /* ---------------- parâmetros e requisição ---------------- */

  function collectParams() {
    const fd = new FormData(form);
    const params = {
      segment: fd.get("segment"),
      count: String(fd.get("count") || "").trim(),
      format: fd.get("format"),
      locale: String(fd.get("locale") || "").trim(),
      seed: String(fd.get("seed") || "").trim(),
      include: String(fd.get("include") || "").trim(),
      exclude: String(fd.get("exclude") || "").trim(),
    };
    Object.keys(params).forEach((k) => { if (params[k] === "") delete params[k]; });
    return params;
  }

  function buildPath(params) {
    // vírgulas ficam legíveis na URL (include/exclude)
    return "/generate?" + new URLSearchParams(params).toString().replace(/%2C/gi, ",");
  }

  function currentUrl() {
    return baseUrl() + buildPath(collectParams());
  }

  function renderRequestLine() {
    els.reqUrl.textContent = buildPath(collectParams());
    const csv = collectParams().format === "csv";
    els.downloadLabel.textContent = csv ? "Baixar CSV" : "Baixar JSON";
  }

  /* ---------------- renderização ---------------- */

  function escapeHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  const TOKEN = /("(?:\\.|[^"\\])*"(\s*:)?|\b(?:true|false|null)\b|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/g;

  function highlightJson(text) {
    return escapeHtml(text).replace(TOKEN, (match, _all, colon) => {
      if (match.startsWith('"')) {
        return colon
          ? `<span class="k">${match.slice(0, match.length - colon.length)}</span>${colon}`
          : `<span class="s">${match}</span>`;
      }
      if (match === "true" || match === "false" || match === "null") return `<span class="l">${match}</span>`;
      return `<span class="n">${match}</span>`;
    });
  }

  function flatten(value, prefix, out) {
    if (value && typeof value === "object" && !Array.isArray(value)) {
      Object.keys(value).forEach((k) => flatten(value[k], prefix ? `${prefix}.${k}` : k, out));
    } else {
      out[prefix] = value;
    }
    return out;
  }

  function renderTable(rows) {
    const flat = rows.map((r) => flatten(r, "", {}));
    const cols = [];
    flat.forEach((r) => Object.keys(r).forEach((k) => { if (!cols.includes(k)) cols.push(k); }));

    const table = document.createElement("table");
    table.className = "data-table";

    const head = table.createTHead().insertRow();
    const th0 = document.createElement("th");
    th0.className = "row-n";
    th0.textContent = "#";
    head.appendChild(th0);
    cols.forEach((c) => {
      const th = document.createElement("th");
      th.scope = "col";
      th.textContent = c;
      head.appendChild(th);
    });

    const body = table.createTBody();
    flat.forEach((row, i) => {
      const tr = body.insertRow();
      const n = tr.insertCell();
      n.className = "row-n";
      n.textContent = String(i + 1);
      cols.forEach((c) => {
        const td = tr.insertCell();
        const v = row[c];
        if (v === null || v === undefined) {
          td.textContent = "null";
          td.className = "is-null";
        } else if (typeof v === "object") {
          td.textContent = JSON.stringify(v);
          td.title = td.textContent;
        } else {
          td.textContent = String(v);
          td.title = td.textContent;
          if (typeof v === "number") td.className = "is-num";
        }
      });
    });

    els.tableWrap.replaceChildren(table);
  }

  function applyView() {
    const csv = state.last && state.last.format === "csv";
    els.tabTable.setAttribute("aria-disabled", csv ? "true" : "false");
    els.tabTable.title = csv ? "A visão em tabela está disponível para JSON" : "";
    if (csv && state.view === "table") state.view = "json";

    const showTable = state.view === "table" && state.last && state.last.data;
    els.viewport.dataset.view = showTable ? "table" : "json";
    els.tabJson.setAttribute("aria-selected", String(!showTable));
    els.tabTable.setAttribute("aria-selected", String(!!showTable));
    els.output.hidden = !!showTable;
    els.tableWrap.hidden = !showTable;
    els.errorBox.hidden = true;
  }

  function showResult(result, ms) {
    state.last = result;

    if (result.format === "json") {
      els.output.innerHTML = highlightJson(result.text);
      renderTable(result.data.data || []);
    } else {
      els.output.textContent = result.text;
      els.tableWrap.replaceChildren();
    }

    els.metaCount.textContent = plural(result.count, "registro", "registros");
    els.metaSize.textContent = formatBytes(new Blob([result.text]).size);
    els.metaTime.textContent = `${ms} ms`;
    els.meta.hidden = false;
    els.btnCopy.disabled = false;
    els.btnDownload.disabled = false;
    els.viewport.scrollTop = 0;
    applyView();
  }

  function showError(title, message) {
    state.last = null;
    els.errorTitle.textContent = title;
    els.errorText.textContent = message;
    els.output.hidden = true;
    els.tableWrap.hidden = true;
    els.errorBox.hidden = false;
    els.meta.hidden = true;
    els.btnCopy.disabled = true;
    els.btnDownload.disabled = true;
    els.viewport.dataset.view = "json";
  }

  /* ---------------- geração ---------------- */

  function apiMessage(text) {
    try {
      const parsed = JSON.parse(text);
      if (parsed && parsed.error) return parsed.error;
    } catch (_) { /* resposta não é JSON */ }
    return null;
  }

  async function generate() {
    if (state.busy) return;
    const params = collectParams();
    const url = baseUrl() + buildPath(params);

    state.busy = true;
    els.btnGenerate.disabled = true;
    els.viewport.dataset.state = "loading";
    const started = performance.now();

    try {
      const res = await fetch(url, { headers: { Accept: params.format === "csv" ? "text/csv" : "application/json" } });
      const text = await res.text();
      const ms = Math.round(performance.now() - started);

      if (!res.ok) {
        const message = apiMessage(text);
        showError(
          message ? "O servidor recusou o pedido" : `Erro ${res.status} no servidor`,
          message || "Verifique os parâmetros e tente novamente."
        );
        return;
      }

      if (params.format === "csv") {
        const lines = text.replace(/\r?\n$/, "").split(/\r?\n/);
        showResult({ text, format: "csv", segment: params.segment, data: null, count: Math.max(lines.length - 1, 0) }, ms);
      } else {
        const data = JSON.parse(text);
        showResult({ text: JSON.stringify(data, null, 2), format: "json", segment: params.segment, data, count: data.count }, ms);
      }
    } catch (err) {
      showError(
        "Não foi possível falar com a API",
        `Confira se o servidor está rodando em ${baseUrl()} e tente de novo.`
      );
      setHealth(false);
    } finally {
      state.busy = false;
      els.btnGenerate.disabled = false;
      els.viewport.dataset.state = "idle";
    }
  }

  /* ---------------- saúde da API e limites ---------------- */

  function setHealth(ok) {
    els.health.dataset.state = ok ? "ok" : "down";
    els.healthText.textContent = ok ? "API online" : "API offline";
  }

  async function checkHealth() {
    els.health.dataset.state = "checking";
    els.healthText.textContent = "Verificando API";
    try {
      const res = await fetch(baseUrl() + "/health", { cache: "no-store" });
      setHealth(res.ok);
    } catch (_) {
      setHealth(false);
    }
  }

  async function loadLimits() {
    try {
      const res = await fetch(baseUrl() + "/api", { cache: "no-store" });
      if (!res.ok) return;
      const info = await res.json();
      if (Number.isInteger(info.max_count) && info.max_count > 0) {
        state.maxCount = info.max_count;
        els.count.max = String(info.max_count);
        document.querySelectorAll("[data-max-count]").forEach((n) => { n.textContent = String(info.max_count); });
        clampCount();
        renderRequestLine();
      }
    } catch (_) { /* mantém o limite padrão */ }
  }

  /* ---------------- quantidade ---------------- */

  function clampCount() {
    let n = parseInt(els.count.value, 10);
    if (Number.isNaN(n)) n = 10;
    els.count.value = String(Math.min(Math.max(n, 1), state.maxCount));
  }

  function stepCount(delta) {
    const n = parseInt(els.count.value, 10) || 1;
    els.count.value = String(n + delta);
    clampCount();
    renderRequestLine();
  }

  /* ---------------- ações ---------------- */

  async function copyOutput() {
    if (!state.last) return;
    toast((await copyText(state.last.text)) ? "Resultado copiado" : "Não foi possível copiar");
  }

  function download() {
    if (!state.last) return;
    const { text, format, segment } = state.last;
    const isCsv = format === "csv";
    // BOM no CSV para o Excel reconhecer os acentos
    const blob = new Blob([isCsv ? "\uFEFF" + text : text], {
      type: isCsv ? "text/csv;charset=utf-8" : "application/json;charset=utf-8",
    });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${segment}_${Date.now()}.${isCsv ? "csv" : "json"}`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    toast(`Arquivo ${isCsv ? "CSV" : "JSON"} baixado`);
  }

  function setTheme(next) {
    document.documentElement.setAttribute("data-theme", next);
    store("dataseed-theme", next);
  }

  /* ---------------- eventos ---------------- */

  form.addEventListener("submit", (e) => { e.preventDefault(); clampCount(); renderRequestLine(); generate(); });
  form.addEventListener("input", renderRequestLine);
  form.addEventListener("change", renderRequestLine);

  document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
      e.preventDefault();
      form.requestSubmit();
    }
  });

  els.count.addEventListener("blur", () => { clampCount(); renderRequestLine(); });
  $("#countDown").addEventListener("click", () => stepCount(-1));
  $("#countUp").addEventListener("click", () => stepCount(1));

  // seed: aceita apenas inteiros
  els.seed.addEventListener("input", () => {
    els.seed.value = els.seed.value.replace(/(?!^-)[^0-9]/g, "");
  });
  $("#seedRandom").addEventListener("click", () => {
    els.seed.value = String(Math.floor(Math.random() * 999999) + 1);
    renderRequestLine();
  });

  els.tabJson.addEventListener("click", () => { state.view = "json"; applyView(); });
  els.tabTable.addEventListener("click", () => {
    if (els.tabTable.getAttribute("aria-disabled") === "true") return;
    state.view = "table";
    applyView();
  });

  els.btnCopy.addEventListener("click", copyOutput);
  els.btnDownload.addEventListener("click", download);
  $("#btnRetry").addEventListener("click", generate);

  $("#copyUrl").addEventListener("click", async () => {
    toast((await copyText(currentUrl())) ? "URL copiada" : "Não foi possível copiar");
  });
  $("#copyCurl").addEventListener("click", async () => {
    toast((await copyText(`curl -s "${currentUrl()}"`)) ? "Comando cURL copiado" : "Não foi possível copiar");
  });

  els.health.addEventListener("click", checkHealth);
  els.apiBase.addEventListener("change", () => { checkHealth(); loadLimits(); });
  $("#themeToggle").addEventListener("click", () => {
    setTheme(document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark");
  });

  // documentação
  $("#btnDocs").addEventListener("click", () => els.docs.showModal());
  $("#closeDocs").addEventListener("click", () => els.docs.close());
  els.docs.addEventListener("click", (e) => { if (e.target === els.docs) els.docs.close(); });

  /* ---------------- inicialização ---------------- */

  renderRequestLine();
  els.btnCopy.disabled = true;
  els.btnDownload.disabled = true;
  checkHealth();
  loadLimits();
  generate(); // a primeira tela já mostra dados reais
})();
