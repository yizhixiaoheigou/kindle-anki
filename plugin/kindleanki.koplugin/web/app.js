/*
 * Browser import page logic: pick an .apkg, inspect it, convert it locally
 * (KindleAnkiConvert), then push the finished pack onto this Kindle.
 * No keys and no card content ever leave the browser except the finished
 * pack upload to the Kindle itself.
 */
(function () {
    "use strict";

    var K = window.KindleApkg;
    var C = window.KindleAnkiConvert;
    var state = {
        fileName: "",
        bytes: null,
        inspect: null,
        fields: [],
        pack: null,
        bundle: null,
        // Set whenever the mapping or title changes, so a stale bundle is
        // never sent after the user edits the fields.
        bundleStale: true,
        busy: false,
        packs: [],
        confirming: null,
    };

    function $(id) { return document.getElementById(id); }
    function esc(value) {
        return String(value == null ? "" : value)
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
    }
    function setError(message) { $("error").textContent = message || ""; }
    function setNote(id, kind, message) {
        var note = $(id);
        note.className = "note" + (kind ? " " + kind : "");
        note.textContent = message || "";
    }
    function setStatus(kind, message) {
        var status = $("device-info");
        status.setAttribute("data-state", kind);
        status.textContent = message;
    }
    function errorText(err) { return (err && err.message) || String(err); }

    // Anki fields hold HTML. Show what a reader sees, not the markup.
    function plainText(raw) {
        var html = String(raw == null ? "" : raw)
            .replace(/<br\s*\/?>/gi, "\n").replace(/<\/(div|p|li)>/gi, "\n");
        var text;
        if (typeof DOMParser !== "undefined") {
            text = new DOMParser().parseFromString(html, "text/html").body.textContent || "";
        } else {
            text = html.replace(/<[^>]*>/g, " ");
        }
        return text.replace(/[ \t ]+/g, " ").replace(/\s*\n\s*/g, "\n").trim();
    }

    // ------------------------------------------------------------------
    // In-app browsers (WeChat and friends)
    // ------------------------------------------------------------------

    // Scanning the Kindle's QR code with WeChat opens this page in WeChat's
    // own browser, where picking an .apkg from Files is awkward and some
    // builds lack DecompressionStream. Say how to move to the real browser.
    var IN_APP = [
        [/MicroMessenger/i, "微信"],
        [/\bQQ\//, "QQ"],
        [/DingTalk/i, "钉钉"],
        [/AlipayClient/i, "支付宝"],
        [/Weibo/i, "微博"],
        [/Lark|Feishu/i, "飞书"],
    ];

    function showInAppHint() {
        var ua = navigator.userAgent || "";
        var app = null;
        IN_APP.forEach(function (entry) {
            if (!app && entry[0].test(ua)) app = entry[1];
        });
        if (!app) return;
        var ios = /iPhone|iPad|iPod/i.test(ua);
        $("inapp-title").textContent = "建议换到" + (ios ? " Safari " : "手机浏览器") + "里打开";
        $("inapp-steps").textContent = "你在" + app + "里打开了这个页面，在这里选 .apkg 文件可能不方便。" +
            "点右上角「···」，选「" + (ios ? "在 Safari 中打开" : "在浏览器打开") + "」，再继续导入。";
        $("inapp").hidden = false;
    }

    // ------------------------------------------------------------------
    // Tabs
    // ------------------------------------------------------------------

    // Suggested provider, filled in while the Kindle has no AI settings yet.
    // The plugin's own AI dialog uses the same pair (main.lua).
    var AI_DEFAULTS = { endpoint: "https://api.deepseek.com", model: "deepseek-flash" };

    // A fresh Kindle gets the defaults so only the key is left to paste.
    // One that is already set up keeps its own: empty fields are not sent,
    // so a key change never overwrites the endpoint or model.
    function prefillAi(configured) {
        if (configured) {
            $("ai-endpoint").placeholder = "留空就保持 Kindle 上现在的接口";
            $("ai-model").placeholder = "留空就保持 Kindle 上现在的模型";
            $("ai-state").textContent = "这台 Kindle 已经设置过 AI。只填要改的项，其他留空。";
            return;
        }
        if (!$("ai-endpoint").value) $("ai-endpoint").value = AI_DEFAULTS.endpoint;
        if (!$("ai-model").value) $("ai-model").value = AI_DEFAULTS.model;
        $("ai-state").textContent = "已填好 DeepSeek 的接口和模型，只需填你的 API key。用别家就直接改这两项。";
    }

    var TABS = ["import", "packs", "ai"];
    function showTab(name) {
        TABS.forEach(function (tab) {
            var selected = tab === name;
            $("tab-" + tab).setAttribute("aria-selected", selected ? "true" : "false");
            $("tab-" + tab).tabIndex = selected ? 0 : -1;
            $("view-" + tab).hidden = !selected;
        });
        setError("");
        if (name === "packs") refreshPacks();
    }

    function onTabKey(event) {
        var index = TABS.indexOf(event.target.id.replace("tab-", ""));
        if (index < 0) return;
        var step = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
        if (!step) return;
        var next = TABS[(index + step + TABS.length) % TABS.length];
        showTab(next);
        $("tab-" + next).focus();
        event.preventDefault();
    }

    // ------------------------------------------------------------------
    // Kindle connection and the packs already on it
    // ------------------------------------------------------------------

    function init() {
        showInAppHint();
        TABS.forEach(function (tab) {
            $("tab-" + tab).addEventListener("click", function () { showTab(tab); });
            $("tab-" + tab).addEventListener("keydown", onTabKey);
        });
        fetch("/api/info").then(function (response) { return response.json(); }).then(function (info) {
            setStatus("ok", "已连接 Kindle" + (info.ip ? "（" + info.ip + "）" : ""));
            prefillAi(info.ai_configured === true);
        }).catch(function () {
            setStatus("down", "连不上 Kindle。确认地址和 Kindle 屏幕上显示的一致，再刷新本页。");
        });
        refreshPacks();
        // The Kindle's "Set up AI" QR code points at #ai, also when this page
        // is already open in the tab the phone reuses.
        if (location.hash === "#ai") showTab("ai");
        window.addEventListener("hashchange", function () {
            if (location.hash === "#ai") showTab("ai");
        });
        $("file").addEventListener("change", function (event) {
            var file = event.target.files && event.target.files[0];
            if (file) onFile(file);
        });
        var drop = $("drop");
        drop.addEventListener("dragover", function (event) {
            event.preventDefault();
            drop.setAttribute("data-over", "");
        });
        drop.addEventListener("dragleave", function () { drop.removeAttribute("data-over"); });
        drop.addEventListener("drop", function (event) {
            event.preventDefault();
            drop.removeAttribute("data-over");
            var file = event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files[0];
            if (file) onFile(file);
        });
        $("pack-title-input").addEventListener("input", function () {
            state.bundleStale = true;
            renderPreviews();
        });
        $("models").addEventListener("change", onFieldChange);
        $("send").addEventListener("click", onSend);
        $("download").addEventListener("click", onDownload);
        $("pack-list").addEventListener("click", onPackListClick);
        $("ai-save").addEventListener("click", onSaveAiSettings);
        if (typeof DecompressionStream === "undefined") {
            setError("这个浏览器解不开 .apkg（需要较新的 Chrome、Safari 或 Firefox）。" +
                "可以换个浏览器，或用电脑上的 Kindle Anki 转换器。");
        }
    }

    function refreshPacks() {
        fetch("/api/packs").then(function (response) { return response.json(); }).then(function (data) {
            state.packs = data.packs || [];
            state.confirming = null;
            renderPacks();
        }).catch(function () {
            setStatus("down", "连不上 Kindle。Kindle 上的导入网页可能已经关闭，在 Kindle 上重新打开后刷新本页。");
        });
    }

    function renderPacks() {
        var packs = state.packs;
        $("pack-count").textContent = packs.length ? String(packs.length) : "";
        var list = $("pack-list");
        if (!packs.length) {
            list.innerHTML = "<li class='empty-state'>Kindle 上还没有卡包。在「导入」里发送一个。</li>";
            return;
        }
        list.innerHTML = packs.map(function (item, index) {
            var confirming = state.confirming === index;
            return "<li class='pack'>" +
                "<div class='pack-row'>" +
                "<span class='pack-title'>" + esc(item.title) +
                "<span class='pack-meta'>" + esc(item.cards) + " 张卡片</span></span>" +
                (confirming ? "" :
                    "<button class='btn danger small' data-action='ask' data-index='" + index + "'>删除</button>") +
                "</div>" +
                (confirming ?
                    "<div class='confirm'><p>删除《" + esc(item.title) + "》？" +
                    "学习进度和 AI 对话会一起删除，无法恢复。</p>" +
                    "<div class='row'>" +
                    "<button class='btn danger small' data-action='delete' data-index='" + index + "'>确认删除</button>" +
                    "<button class='btn small' data-action='cancel'>取消</button></div></div>" : "") +
                "</li>";
        }).join("");
    }

    function onPackListClick(event) {
        var button = event.target.closest && event.target.closest("button[data-action]");
        if (!button) return;
        var action = button.getAttribute("data-action");
        var index = Number(button.getAttribute("data-index"));
        if (action === "ask") {
            state.confirming = index;
            renderPacks();
        } else if (action === "cancel") {
            state.confirming = null;
            renderPacks();
        } else if (action === "delete") {
            onDeletePack(state.packs[index], button);
        }
    }

    function onDeletePack(item, button) {
        var fileName = item && item.name;
        if (!fileName) return;
        button.disabled = true;
        button.textContent = "正在删除…";
        fetch("/api/packs?name=" + encodeURIComponent(fileName), { method: "DELETE" })
            .then(function (response) { return response.json(); })
            .then(function (result) {
                if (!result.ok) {
                    setError("没删掉《" + item.title + "》：" + (result.error || "Kindle 没有说明原因"));
                }
                refreshPacks();
            }).catch(function (err) {
                setError("没删掉《" + item.title + "》：" + errorText(err));
                refreshPacks();
            });
    }

    // ------------------------------------------------------------------
    // Step 1: the .apkg file
    // ------------------------------------------------------------------

    function lockStep(id, locked) {
        if (locked) $(id).setAttribute("data-locked", "");
        else $(id).removeAttribute("data-locked");
    }

    function onFile(file) {
        if (typeof K === "undefined" || typeof C === "undefined") {
            setError("页面脚本没有加载完整（apkg.js 或 convert.js）。刷新本页再试。");
            return;
        }
        if (!/\.apkg$/i.test(file.name)) {
            setError("这不是 .apkg 文件。在 Anki 里用「导出」生成 .apkg。");
            return;
        }
        setError("");
        setNote("report", "", "");
        state.pack = null;
        state.bundle = null;
        state.bundleStale = true;
        state.fields = [];
        $("pack-title-input").value = "";
        $("mapping").hidden = true;
        lockStep("step2", true);
        lockStep("step3", true);
        $("drop").setAttribute("data-picked", "");
        $("drop-title").textContent = file.name;
        $("file-name").textContent = "正在读取…（" + Math.max(1, Math.round(file.size / 1024)) + " KB）";
        var reader = new FileReader();
        reader.onload = function () {
            state.bytes = new Uint8Array(reader.result);
            state.fileName = file.name;
            C.inspectApkg(state.bytes, file.name).then(function (info) {
                state.inspect = info;
                $("file-name").textContent = "已读取。点这里可以换一个文件";
                renderModels(info);
                $("mapping").hidden = false;
                $("step2-hint").textContent =
                    "每种笔记至少选一个正面字段和一个背面字段。下面的预览就是卡片在 Kindle 上的样子。";
                lockStep("step2", false);
                lockStep("step3", false);
                $("step2").scrollIntoView({ block: "start", behavior: "smooth" });
            }).catch(function (err) {
                $("file-name").textContent = "读不了这个文件。点这里换一个";
                setError("读不了这个 .apkg：" + errorText(err) + "。导出时记得勾选「支持旧版本 Anki」。");
            });
        };
        reader.onerror = function () {
            $("file-name").textContent = "读不了这个文件。点这里换一个";
            setError("浏览器读不了所选文件。");
        };
        reader.readAsArrayBuffer(file);
    }

    // ------------------------------------------------------------------
    // Step 2: field mapping and the Kindle preview
    // ------------------------------------------------------------------

    // Mirrors the desktop converter: under every field show a muted
    // "例如 …" snippet of that field's own content from the first real note,
    // so cryptic field names are identifiable at a glance.
    function fieldSample(sample, fieldIndex) {
        var text = plainText(sample && sample[fieldIndex]).replace(/\s+/g, " ");
        if (!text) return "";
        if (text.length > 40) text = text.slice(0, 40).replace(/\s+$/, "") + "…";
        return esc(text);
    }

    function fieldRows(model, index) {
        return model.fields.map(function (name, fieldIndex) {
            var sample = fieldSample(model.sample, fieldIndex);
            var label = esc(name || "字段" + (fieldIndex + 1));
            function chip(side, text) {
                return "<label class='chip'><input type='checkbox' data-model='" + index +
                    "' data-side='" + side + "' value='" + fieldIndex +
                    "' aria-label='" + label + " 放" + text + "'><span>" + text + "</span></label>";
            }
            return "<li><span class='field-name'>" + label + "</span>" +
                "<span class='sides'>" + chip("front", "正面") + chip("back", "背面") + "</span>" +
                (sample ? "<span class='field-sample'>例如 " + sample + "</span>" : "") +
                "</li>";
        }).join("");
    }

    function renderModels(info) {
        $("pack-title-input").placeholder = info.suggested_title || info.title || "留空就用文件名";
        state.fields = info.models.map(function () { return { front: [], back: [] }; });
        var host = $("models");
        if (!info.models.length) {
            host.innerHTML = "<p class='note err'>这个文件里没有能识别的笔记类型。</p>";
            return;
        }
        host.innerHTML = info.models.map(function (model, index) {
            return "<div class='model' id='model-" + index + "' data-incomplete='true'>" +
                "<div class='model-fields'>" +
                "<h3>" + esc(model.name) + "</h3>" +
                "<p class='need' id='need-" + index + "'></p>" +
                "<ul class='fields'>" + fieldRows(model, index) + "</ul>" +
                "</div>" +
                "<div class='model-preview'>" +
                "<div class='preview' aria-hidden='true'><div class='kindle'>" +
                "<div class='screen' id='screen-" + index + "'></div></div></div>" +
                "<p class='preview-caption'>用这种笔记的第一条预览</p>" +
                "</div></div>";
        }).join("");
        renderPreviews();
    }

    function sideText(model, list) {
        return list.map(function (fieldIndex) {
            return plainText(model.sample && model.sample[fieldIndex]);
        }).filter(Boolean).join("\n");
    }

    function renderPreviews() {
        if (!state.inspect) return;
        var title = $("pack-title-input").value.trim() || $("pack-title-input").placeholder;
        state.inspect.models.forEach(function (model, index) {
            var fields = state.fields[index];
            var complete = fields.front.length > 0 && fields.back.length > 0;
            $("model-" + index).setAttribute("data-incomplete", complete ? "false" : "true");
            if (complete) $("model-" + index).removeAttribute("data-flagged");
            $("need-" + index).textContent = complete ? "已选好" :
                !fields.front.length && !fields.back.length ? "还没选字段" :
                !fields.front.length ? "还差正面字段" : "还差背面字段";
            var front = sideText(model, fields.front);
            var back = sideText(model, fields.back);
            var emptyField = "（这个字段在第一条笔记里是空的）";
            $("screen-" + index).innerHTML =
                "<div class='bar'><span>" + esc(title) + "</span><span>1 / 1</span></div>" +
                (fields.front.length ? "<div class='front'>" + esc(front || emptyField) + "</div>"
                    : "<div class='front empty'>选一个正面字段，问题会显示在这里</div>") +
                "<div class='divider'></div>" +
                (fields.back.length ? "<div class='back'>" + esc(back || emptyField) + "</div>"
                    : "<div class='back empty'>选一个背面字段，答案会显示在这里</div>");
        });
    }

    function onFieldChange(event) {
        var input = event.target;
        if (!input || !input.dataset || input.dataset.model == null) return;
        var index = Number(input.dataset.model);
        var side = input.dataset.side;
        var value = Number(input.value);
        var list = state.fields[index] && state.fields[index][side];
        if (!list) return;
        var position = list.indexOf(value);
        if (input.checked && position < 0) list.push(value);
        if (!input.checked && position >= 0) list.splice(position, 1);
        list.sort(function (a, b) { return a - b; });
        state.bundleStale = true;
        renderPreviews();
    }

    function currentMapping() {
        var mapping = {};
        if (!state.inspect) return mapping;
        state.inspect.models.forEach(function (model, index) {
            mapping[String(model.id)] = {
                front: state.fields[index].front,
                back: state.fields[index].back,
            };
        });
        return mapping;
    }

    function incompleteModel() {
        if (!state.inspect) return null;
        for (var index = 0; index < state.inspect.models.length; index++) {
            var fields = state.fields[index] || {};
            if (!fields.front.length || !fields.back.length) {
                return { name: state.inspect.models[index].name, index: index };
            }
        }
        return null;
    }

    // ------------------------------------------------------------------
    // Step 3: convert, then send or download
    // ------------------------------------------------------------------

    function skipSummary(reasons) {
        var names = {
            unsupported_model: "笔记类型不支持",
            non_primary_template: "非主模板",
            missing_deck: "缺少牌组",
            empty_front: "正面为空",
            empty_back: "背面为空",
            not_enough_options: "选项不足",
            unreadable_correct_answer: "无法识别答案",
        };
        return Object.keys(reasons).map(function (key) {
            return (names[key] || key) + " " + reasons[key];
        }).join("，");
    }

    function setBusy(label) {
        state.busy = !!label;
        $("send").disabled = state.busy;
        $("download").disabled = state.busy;
        $("send").textContent = label || "转换并发送到 Kindle";
    }

    // Resolves to the bundle for the current mapping, converting only when
    // the mapping or title changed since the last conversion.
    function convert() {
        if (!state.bytes) return Promise.reject(new Error("先在第 1 步选择 .apkg 文件。"));
        var missing = incompleteModel();
        if (missing) {
            state.fields.forEach(function (fields, index) {
                if (!fields.front.length || !fields.back.length) {
                    $("model-" + index).setAttribute("data-flagged", "");
                }
            });
            $("model-" + missing.index).scrollIntoView({ block: "center", behavior: "smooth" });
            return Promise.reject(new Error("「" + missing.name + "」还没选好：正面和背面字段每项至少一个。"));
        }
        if (state.bundle && !state.bundleStale) return Promise.resolve(state.bundle);
        var title = $("pack-title-input").value.trim();
        return C.importApkg(state.bytes, state.fileName, {
            ai: {},
            fieldMapping: currentMapping(),
            title: title || null,
        }).then(function (pack) {
            state.pack = pack;
            return C.writeKindleBundle(pack, C.openArchive(state.bytes, state.fileName),
                { fileName: state.fileName });
        }).then(function (bundle) {
            state.bundle = bundle;
            state.bundleStale = false;
            return bundle;
        });
    }

    function conversionSummary() {
        var report = state.pack.report;
        return report.imported_cards + " 张卡片，" + state.pack.decks.length + " 个牌组" +
            (report.media_files ? "，图片 " + report.media_files + " 张" : "") +
            (report.skipped_cards ? "。跳过 " + report.skipped_cards + " 张（" +
                skipSummary(report.skipped_reasons) + "）" : "");
    }

    function onSend() {
        if (state.busy) return;
        setError("");
        setNote("report", "", "");
        setBusy("正在转换…");
        convert().then(function (bundle) {
            setBusy("正在发送到 Kindle…");
            return fetch("/api/packs?name=" + encodeURIComponent(bundle.stem), {
                method: "POST",
                headers: { "Content-Type": "application/zip" },
                body: bundle.zipBytes,
            }).then(function (response) { return response.json(); });
        }).then(function (result) {
            setBusy("");
            if (result.ok && result.existing) {
                setNote("report", "info", "Kindle 上已经有《" + result.title + "》，这次没有覆盖。\n" +
                    "要换成新版本，先在「卡包」里删除旧的，再发送一次。");
            } else if (result.ok) {
                setNote("report", "ok", "已发送到 Kindle：《" + result.title + "》，" + conversionSummary() +
                    "。\n在 Kindle 上打开「我的卡包」就能开始学。");
            } else {
                setNote("report", "err", "Kindle 没收下这个卡包：" + (result.error || "没有说明原因"));
            }
            refreshPacks();
        }).catch(function (err) {
            setBusy("");
            setNote("report", "err", errorText(err));
        });
    }

    function onDownload() {
        if (state.busy || typeof Blob === "undefined") return;
        setError("");
        setBusy("正在转换…");
        convert().then(function (bundle) {
            setBusy("");
            var blob = new Blob([bundle.zipBytes], { type: "application/zip" });
            var link = document.createElement("a");
            link.href = URL.createObjectURL(blob);
            link.download = bundle.zipName;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            setTimeout(function () { URL.revokeObjectURL(link.href); }, 5000);
            setNote("report", "ok", "已下载 " + bundle.zipName + "：" + conversionSummary() + "。");
        }).catch(function (err) {
            setBusy("");
            setNote("report", "err", errorText(err));
        });
    }

    // ------------------------------------------------------------------
    // AI settings
    // ------------------------------------------------------------------

    function onSaveAiSettings() {
        var fields = {
            endpoint: $("ai-endpoint").value.trim(),
            model: $("ai-model").value.trim(),
            api_key: $("ai-key").value.trim(),
            system_prompt: $("ai-prompt").value.trim(),
        };
        var code = $("ai-code").value.trim();
        if (!/^\d{4}$/.test(code)) {
            setNote("ai-result", "err", "填 Kindle 弹窗里显示的 4 位配对码。");
            $("ai-code").focus();
            return;
        }
        if (!fields.endpoint && !fields.model && !fields.api_key && !fields.system_prompt) {
            setNote("ai-result", "err", "至少填一项再保存。没填的项保持 Kindle 上原来的值。");
            return;
        }
        $("ai-save").disabled = true;
        $("ai-save").textContent = "正在保存…";
        fetch("/api/ai-settings?code=" + encodeURIComponent(code), {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(fields),
        }).then(function (response) { return response.json(); }).then(function (payload) {
            if (payload.ok) {
                var summary = "已保存到 Kindle。";
                if (payload.endpoint) summary += "\n接口：" + payload.endpoint;
                if (payload.model) summary += "\n模型：" + payload.model;
                if (payload.key_masked) summary += "\nkey：" + payload.key_masked;
                setNote("ai-result", "ok", summary);
                $("ai-key").value = "";
            } else {
                setNote("ai-result", "err", "没保存：" + (payload.error || "Kindle 没有说明原因"));
            }
        }).catch(function (err) {
            setNote("ai-result", "err", "没保存：" + errorText(err));
        }).then(function () {
            $("ai-save").disabled = false;
            $("ai-save").textContent = "保存到 Kindle";
        });
    }

    init();
})();
