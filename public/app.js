

(function () {
    const byId = (id) => document.getElementById(id);

    const els = {
        // actions/global
        btnGenerate: byId("btnGenerate"),
        btnDownloadCsv: byId("btnDownloadCsv"),
        btnHealth: byId("btnHealth"),
        btnCopyJson: byId("btnCopyJson"),
        copyCurl: byId("copyCurl"),
        themeToggle: byId("themeToggle"),

        status: byId("status"),
        output: byId("output"),
        skeleton: byId("skeleton"),
        toast: byId("toast"),
        tabs: document.querySelectorAll(".tab"),
        apiBaseGlobal: byId("apiBase"), // se for único fora das tabs
    };

    // helpers de aba

    function activeTabName() {
        return document.querySelector(".tab.active")?.dataset.tab || "simple"; // "simple" | "advanced"
    }
    function activeTabEl() {
        return document.getElementById(`tab-${activeTabName()}`);
    }
    function isAdvanced() { return activeTabName() === "advanced"; }

        // busca elemento DENTRO da aba ativa (evita IDs duplicados)
    function getInActiveTab(id) {
        return activeTabEl()?.querySelector(`#${id}`) || byId(id); // fallback se for único
    }


    function clearResult() {
        const statusEl = document.getElementById("status");
        const outputEl = document.getElementById("output");
        const skeleton = document.getElementById("skeleton");
        const toast    = document.getElementById("toast");

        if (outputEl) outputEl.textContent = "";
        if (statusEl) { statusEl.textContent = "Aguardando…"; statusEl.style.color = "var(--accent)"; }
        if (skeleton) skeleton.classList.add("hidden");
        if (toast) toast.classList.add("hidden");
    }

    function clearAdvancedFields() {
        // pega dentro da aba advanced por segurança
        const adv = document.getElementById("tab-advanced");
        adv?.querySelector("#seed") && (adv.querySelector("#seed").value = "");
        adv?.querySelector("#fieldsFilter") && (adv.querySelector("#fieldsFilter").value = "");
        adv?.querySelector("#limitDisplay") && (adv.querySelector("#limitDisplay").value = 10);
        adv?.querySelector("#includeFields") && (adv.querySelector("#includeFields").value = "");
        adv?.querySelector("#excludeFields") && (adv.querySelector("#excludeFields").value = "");
    }

    function updateCopyVisibility() {
        const formatEl = getInActiveTab("format");
        const isJson = formatEl?.value === "json";
        const inSimple = activeTabName() === "simple";
        els.btnCopyJson?.classList.toggle("hidden", !(isJson && inSimple));
    }

    // URL builder
    function apiUrl(path, params = {}) {
        const base = (els.apiBaseGlobal?.value || "").trim();
        const url = new URL((base || window.location.origin) + path);
        Object.entries(params).forEach(([k, v]) => {
            if (v !== undefined && v !== null && String(v).length > 0) {
                url.searchParams.set(k, v);
            }
        });
        return url.toString();
    }

    // coleta de parâmetros somente da aba ativa

    function collectParams(forceFormat) {
        // Pega "format" e demais do container ativo (evita IDs duplicados)
        const tabId = activeTabName() === "advanced" ? "#tab-advanced" : "#tab-simple";

        const segmentEl = document.querySelector(`${tabId} #segment`) || document.getElementById("segment");
        const countEl   = document.querySelector(`${tabId} #count`)   || document.getElementById("count");
        const formatEl  = document.querySelector(`${tabId} #format`)  || document.getElementById("format");
        const localeEl  = document.querySelector(`${tabId} #locale`)  || document.getElementById("locale");

        const localeVal = (localeEl?.value || "").trim() || "pt-BR";

        const params = {
            mode: activeTabName(), // <- envia o modo explicitamente
            segment: segmentEl?.value,
            count: countEl?.value,
            format: forceFormat || formatEl?.value || "json",
            locale: localeVal,
        };

        if (isAdvanced()) {
            // Só Avançado envia estes
            const seedEl     = document.querySelector("#tab-advanced #seed");
            const includeEl  = document.querySelector("#tab-advanced #includeFields");
            const excludeEl  = document.querySelector("#tab-advanced #excludeFields");

            const seed    = (seedEl?.value || "").trim();
            const include = (includeEl?.value || "").trim();
            const exclude = (excludeEl?.value || "").trim();

            if (seed)   params.seed   = seed;
            if (include) params.include = include;
            if (exclude) params.exclude = exclude;
        }

        // Remove chave vazia
        Object.keys(params).forEach(k => {
            if (params[k] === undefined || params[k] === null || String(params[k]).trim() === "") {
                delete params[k];
            }
        });

        return params;
    }

    async function fetchJson(url) {
        const res = await fetch(url, { headers: { "Accept": "application/json" } });
        if (!res.ok) throw new Error(`HTTP ${res.status} — ${await res.text()}`);
        return res.json();
    }

    function showToast(msg) {
        if (!els.toast) return;
        els.toast.textContent = msg;
        els.toast.classList.remove("hidden");
        setTimeout(() => els.toast.classList.add("hidden"), 2500);
    }

    function showSkeleton(show) {
        els.skeleton?.classList.toggle("hidden", !show);
        if (show) els.output && (els.output.textContent = "");
    }

    function showOutput(obj) {
        try { els.output.textContent = typeof obj === "string" ? obj : JSON.stringify(obj, null, 2); }
        catch { els.output.textContent = String(obj); }
    }

    // preview avançado (filtro/limite) — só advanced
    function filterFieldsInArray(arr, filterStr) {
        if (!filterStr) return arr;
        const removals = filterStr.split(",").map(s => s.trim()).filter(Boolean).map(s => s.replace(/^-/, ""));
        return arr.map(item => {
            const copy = JSON.parse(JSON.stringify(item));
            removals.forEach(field => { delete copy[field]; });
            return copy;
        });
    }

    function applyAdvancedPreview(out) {
        if (!isAdvanced()) return out; // <- guarda aqui!
        const filterEl = document.querySelector("#tab-advanced #fieldsFilter");
        const limitEl  = document.querySelector("#tab-advanced #limitDisplay");

        const filterStr = (filterEl?.value || "").trim();
        const limit = parseInt((limitEl?.value || "10"), 10);

        // remove campos do preview (client-side)
        const removals = filterStr
            .split(",").map(s => s.trim()).filter(Boolean)
            .map(s => s.replace(/^-/, ""));
        const filtered = (Array.isArray(out) ? out : [out]).map(item => {
            const copy = JSON.parse(JSON.stringify(item));
            removals.forEach(field => { delete copy[field]; });
            return copy;
        });
        return Array.isArray(out) ? filtered.slice(0, limit) : filtered[0];
    }

    // actions
    async function onGenerate() {
        try {
            setStatus("Gerando dados...");
            showSkeleton(true);

            const params = collectParams(); // coleta apenas da aba ativa
            const url = apiUrl("/generate", params);

            if ((params.format || "json") === "json") {
                const data = await fetchJson(url);
                const total = Array.isArray(data.data) ? data.data.length : 1;
                let preview = data.data || data;
                preview = applyAdvancedPreview(preview);

                setStatus(`OK — ${total} registros`);
                showSkeleton(false);
                showOutput({ ...data, data: preview });
                showToast(isAdvanced() ? "Dados gerados (preview avançado)" : "Dados gerados");
            } else {
                const res = await fetch(url);
                if (!res.ok) throw new Error(`HTTP ${res.status} — ${await res.text()}`);
                const blob = await res.blob();
                const text = await blob.text();
                setStatus("OK (CSV gerado)");
                showSkeleton(false);
                showOutput(text);
                showToast("CSV pronto (preview). Use ‘Baixar CSV’ para download.");
            }
        } catch (err) {
            console.error(err);
            setStatus(err.message || "Erro ao gerar", true);
            showSkeleton(false);
            showOutput({ error: err.message });
            showToast("Falha ao gerar");
        }
    }

    async function onDownloadCsv() {
        try {
            const params = collectParams("csv"); // força CSV
            const url = apiUrl("/generate", params);
            const res = await fetch(url);
            if (!res.ok) throw new Error(`HTTP ${res.status} — ${await res.text()}`);
            const blob = await res.blob();
            const fileName = `${params.segment}_${Date.now()}.csv`;

            const a = document.createElement("a");
            a.href = URL.createObjectURL(blob);
            a.download = fileName;
            document.body.appendChild(a);
            a.click();
            a.remove();

            setStatus(`CSV baixado: ${fileName}`);
            showToast("Download iniciado");
        } catch (err) {
            console.error(err);
            setStatus(err.message || "Erro ao baixar CSV", true);
            showOutput({ error: err.message });
            showToast("Falha no download");
        }
    }

    async function onHealth() {
        try {
            setStatus("Checando saúde...");
            const url = apiUrl("/health");
            const data = await fetchJson(url);
            setStatus("OK");
            showOutput(data);
            showToast("Servidor saudável");
        } catch (err) {
            console.error(err);
            setStatus(err.message || "Erro no health", true);
            showOutput({ error: err.message });
            showToast("Falha no health");
        }
    }

    async function onCopyJson() {
        // segurança extra: apenas Simples + JSON
        const formatEl = getInActiveTab("format");
        const inSimpleJson = (activeTabName() === "simple") && (formatEl?.value === "json");
        if (!inSimpleJson) return;
        const text = els.output?.textContent || "";
        if (!text.trim()) { showToast("Nada para copiar"); return; }
        try { await navigator.clipboard.writeText(text); showToast("JSON copiado"); }
        catch { showToast("Falha ao copiar"); }
    }

    function setStatus(msg, isError = false) {
        els.status.textContent = msg;
        els.status.style.color = isError ? "#f87171" : "var(--accent)";
    }


    function setupTabs() {
        document.querySelectorAll(".tab").forEach(btn => {
            btn.addEventListener("click", () => {
                // alterna ativo
                document.querySelectorAll(".tab").forEach(b => b.classList.remove("active"));
                btn.classList.add("active");
                // mostra conteúdo da tab
                document.querySelectorAll(".tab-content").forEach(c => c.classList.remove("active"));
                document.getElementById(`tab-${btn.dataset.tab}`)?.classList.add("active");

                clearResult(); // sempre limpa ao trocar de aba

                if (btn.dataset.tab === "simple") {
                    clearAdvancedFields(); // <- zera avançado ao voltar pra Simples
                }

                updateCopyVisibility(); // botão Copiar só em Simples + JSON
            });
        });
    }

    // bindings
    els.btnGenerate?.addEventListener("click", onGenerate);
    els.btnDownloadCsv?.addEventListener("click", onDownloadCsv);
    els.btnHealth?.addEventListener("click", onHealth);
    els.btnCopyJson?.addEventListener("click", onCopyJson);

    // copiar cURL (sempre modo simple para exemplo)
    els.copyCurl?.addEventListener("click", async () => {
        const base = els.apiBaseGlobal?.value || window.location.origin;
        const url = `${base}/generate?segment=pf&count=5&format=json&locale=pt-BR&mode=simple`;
        const cmd = `curl -s "${url}" | jq`;
        try { await navigator.clipboard.writeText(cmd); showToast("Exemplo cURL copiado"); }
        catch { showToast("Falha ao copiar cURL"); }
    });

    // toggle tema
    els.themeToggle?.addEventListener("click", () => {
        const html = document.documentElement;
        const next = (html.getAttribute("data-theme") || "dark") === "dark" ? "light" : "dark";
        html.setAttribute("data-theme", next);
        showToast(`Tema: ${next}`);
    });

    // mensagem contextual para CSV + visibilidade do Copiar
    // ⚠️ importante: pegar format do container ativo
    const formatSimple = document.querySelector("#tab-simple #format");
    const formatAdvanced = document.querySelector("#tab-advanced #format");
    [formatSimple, formatAdvanced].forEach(el => {
        el?.addEventListener("change", () => {
            if (el.value === "csv") setStatus("Formato CSV: use ‘Gerar dados’ para preview ou ‘Baixar CSV’ para download.");
            else setStatus("Aguardando…");
            updateCopyVisibility();
        });
    });

    // limpar preview ao mudar campos chave
    ["segment", "locale", "count"].forEach(id => {
        document.querySelector(`#tab-simple #${id}`)?.addEventListener("change", clearResult);
        document.querySelector(`#tab-advanced #${id}`)?.addEventListener("change", clearResult);
    });

    // init
    setupTabs();
    updateCopyVisibility();
    setStatus("Aguardando…");
})();
