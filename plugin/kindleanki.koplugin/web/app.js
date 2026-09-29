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
        dirty: {},
        titleEdited: false,
        pack: null,
        bundle: null,
    };

    function $(id) { return document.getElementById(id); }
    function esc(value) {
        return String(value == null ? "" : value)
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }
    function setError(message) { $("error").textContent = message || ""; }

    function init() {
        fetch("/api/info").then(function (response) { return response.json(); }).then(function (info) {
            $("device-info").textContent = "已连接这台 Kindle（卡包目录 " + (info.packs_dir || "") + "）";
        }).catch(function () {
            $("device-info").textContent =
                "连接失败：请刷新本页重试；若仍失败，请确认地址与 Kindle 屏幕上显示的一致（http://<Kindle IP>:8767）。";
        });
        refreshPacks();
        $("file").addEventListener("change", onFile);
        $("pack-title-input").addEventListener("input", function () {
            state.titleEdited = true;
        });
        $("models").addEventListener("change", onFieldChange);
        $("convert").addEventListener("click", onConvert);
        $("upload").addEventListener("click", onUpload);
        $("download").addEventListener("click", onDownload);
        $("ai-save").addEventListener("click", onSaveAiSettings);
        if (typeof DecompressionStream === "undefined") {
            setError("此浏览器不支持解压 .apkg（需要较新的 Chrome / Safari / Firefox），请改用电脑转换器。");
        }
    }

    function refreshPacks() {
        fetch("/api/packs").then(function (response) { return response.json(); }).then(function (data) {
            var list = $("pack-list");
            list.innerHTML = "";
            var packs = data.packs || [];
            if (!packs.length) {
                list.innerHTML = "<li><span>（还没有卡包）</span></li>";
                return;
            }
            packs.forEach(function (item) {
                var li = document.createElement("li");
                var label = document.createElement("span");
                label.textContent = item.title + "（" + item.cards + " 张）";
                var button = document.createElement("button");
                button.textContent = "删除";
                button.addEventListener("click", function () { onDeletePack(item, button); });
                li.appendChild(label);
                li.appendChild(button);
                list.appendChild(li);
            });
        }).catch(function () { });
    }

    function onDeletePack(item, button) {
        var fileName = item.name || "";
        if (!fileName) return;
        var message = "删除《" + item.title + "》？\n学习进度和 AI 对话会一起删除，无法恢复。";
        if (typeof confirm === "function" && !confirm(message)) return;
        button.disabled = true;
        fetch("/api/packs?name=" + encodeURIComponent(fileName), { method: "DELETE" })
            .then(function (response) { return response.json(); })
            .then(function (result) {
                if (result.ok) {
                    refreshPacks();
                } else {
                    button.disabled = false;
                    setError("删除失败：" + (result.error || "未知错误"));
                }
            }).catch(function (err) {
                button.disabled = false;
                setError("删除失败：" + ((err && err.message) || err));
            });
    }

    function onFile(event) {
        var file = event.target.files && event.target.files[0];
        if (!file) return;
        if (typeof K === "undefined" || typeof C === "undefined") {
            setError("页面脚本没有加载完整（apkg.js / convert.js 缺失）——请刷新本页重试。");
            return;
        }
        setError("");
        state.pack = null;
        state.bundle = null;
        state.dirty = {};
        state.fields = [];
        state.titleEdited = false;
        $("step2").hidden = true;
        $("step3").hidden = true;
        $("report").textContent = "";
        $("upload").disabled = true;
        $("download").disabled = true;
        $("file-name").textContent = file.name + "（" + Math.round(file.size / 1024) + " KB）";
        var reader = new FileReader();
        reader.onload = function () {
            state.bytes = new Uint8Array(reader.result);
            state.fileName = file.name;
            C.inspectApkg(state.bytes, file.name).then(function (info) {
                state.inspect = info;
                renderModels(info);
                $("step2").hidden = false;
                $("step3").hidden = false;
                window.scrollTo(0, document.body.scrollHeight);
            }).catch(function (err) {
                setError("读取失败：" + ((err && err.message) || err));
            });
        };
        reader.onerror = function () {
            setError("无法读取所选文件。");
        };
        reader.readAsArrayBuffer(file);
    }

    // Mirrors the desktop converter: under every field checkbox show a muted
    // "例如 …" snippet of that field's own content from the first real note,
    // so cryptic field names are identifiable at a glance.
    function fieldSample(sample, fieldIndex) {
        var raw = sample && sample[fieldIndex];
        if (raw == null) return "";
        var text = String(raw).split(/\s+/).filter(Boolean).join(" ");
        if (!text) return "";
        if (text.length > 24) {
            text = text.slice(0, 24).replace(/\s+$/, "");
        }
        return esc(text);
    }

    function checkboxRow(model, side, index) {
        return model.fields.map(function (name, fieldIndex) {
            var sample = fieldSample(model.sample, fieldIndex);
            return "<label class=\"field\"><input type=\"checkbox\" data-model=\"" + index +
                "\" data-side=\"" + side + "\" value=\"" + fieldIndex + "\">" +
                "<span class=\"field-name\">" +
                esc(name || "字段" + (fieldIndex + 1)) + "</span>" +
                (sample ? "<span class=\"field-sample\">例如 " + sample + "</span>" : "") +
                "</label>";
        }).join("");
    }

    function renderModels(info) {
        var host = $("models");
        host.innerHTML = "";
        if (!state.titleEdited) {
            $("pack-title-input").value = info.suggested_title || info.title || "";
        }
        if (!info.models.length) {
            host.innerHTML = "<p class='warn'>没有可识别的笔记类型。</p>";
        }
        state.fields = info.models.map(function () {
            return { front: [], back: [] };
        });
        info.models.forEach(function (model, index) {
            var div = document.createElement("div");
            div.className = "model";
            div.innerHTML =
                "<h3>" + esc(model.name) + "</h3>" +
                "<div class='row'><span>正面字段</span>" + checkboxRow(model, "front", index) + "</div>" +
                "<div class='row'><span>背面字段</span>" + checkboxRow(model, "back", index) + "</div>";
            host.appendChild(div);
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
        state.dirty[index] = true;
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
                return state.inspect.models[index].name;
            }
        }
        return null;
    }

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

    function onConvert() {
        if (!state.bytes) return;
        var missing = incompleteModel();
        if (missing) {
            setError("请先为「" + missing + "」勾选正面字段和背面字段（每项至少一个）。");
            return;
        }
        setError("");
        $("convert").disabled = true;
        var title = $("pack-title-input").value.trim();
        C.importApkg(state.bytes, state.fileName, {
            ai: {},
            fieldMapping: currentMapping(),
            title: state.titleEdited ? title : null,
        }).then(function (pack) {
            state.pack = pack;
            return C.writeKindleBundle(pack, C.openArchive(state.bytes, state.fileName),
                { fileName: state.fileName });
        }).then(function (bundle) {
            state.bundle = bundle;
            var report = state.pack.report;
            $("report").textContent = "转换成功：" + report.imported_cards + "/" + report.total_cards +
                " 张卡片，" + state.pack.decks.length + " 个牌组" +
                (report.media_files ? "，图片 " + report.media_files + " 张" : "") +
                (report.skipped_cards ? "；跳过 " + report.skipped_cards + " 张（" +
                    skipSummary(report.skipped_reasons) + "）" : "");
            $("upload").disabled = false;
            $("download").disabled = false;
            $("convert").disabled = false;
        }).catch(function (err) {
            setError("转换失败：" + ((err && err.message) || err) + "。可改用电脑上的 Kindle Anki 转换器。");
            $("convert").disabled = false;
        });
    }

    function onUpload() {
        var bundle = state.bundle;
        if (!bundle) return;
        setError("");
        $("upload").disabled = true;
        fetch("/api/packs?name=" + encodeURIComponent(bundle.stem), {
            method: "POST",
            headers: { "Content-Type": "application/zip" },
            body: bundle.zipBytes,
        }).then(function (response) { return response.json(); }).then(function (result) {
            if (result.ok) {
                $("report").textContent = "已导入 Kindle：《" + result.title + "》（" + result.cards +
                    " 张）。现在可以在 Kindle 上打开卡包了。";
                refreshPacks();
            } else {
                setError("Kindle 导入失败：" + (result.error || "未知错误"));
                $("upload").disabled = false;
            }
        }).catch(function (err) {
            setError("上传失败：" + ((err && err.message) || err));
            $("upload").disabled = false;
        });
    }

    function onDownload() {
        var bundle = state.bundle;
        if (!bundle || typeof Blob === "undefined") return;
        var blob = new Blob([bundle.zipBytes], { type: "application/zip" });
        var link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = bundle.zipName;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        setTimeout(function () { URL.revokeObjectURL(link.href); }, 5000);
    }

    function onSaveAiSettings() {
        var fields = {
            endpoint: $("ai-endpoint").value.trim(),
            model: $("ai-model").value.trim(),
            api_key: $("ai-key").value.trim(),
            system_prompt: $("ai-prompt").value.trim(),
        };
        var code = $("ai-code").value.trim();
        var result = $("ai-result");
        result.className = "";
        if (!code) {
            result.className = "err";
            result.textContent = "请先填 Kindle 弹窗里显示的 4 位配对码。";
            return;
        }
        if (!fields.endpoint && !fields.model && !fields.api_key && !fields.system_prompt) {
            result.className = "err";
            result.textContent = "至少填一项再保存。";
            return;
        }
        $("ai-save").disabled = true;
        fetch("/api/ai-settings?code=" + encodeURIComponent(code), {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(fields),
        }).then(function (response) { return response.json(); }).then(function (payload) {
            if (payload.ok) {
                var summary = "已保存到 Kindle。";
                if (payload.endpoint) summary += "\nendpoint: " + payload.endpoint;
                if (payload.model) summary += "\nmodel: " + payload.model;
                if (payload.key_masked) summary += "\nkey: " + payload.key_masked;
                result.textContent = summary;
            } else {
                result.className = "err";
                result.textContent = "保存失败：" + (payload.error || "未知错误");
            }
            $("ai-save").disabled = false;
        }).catch(function (err) {
            result.className = "err";
            result.textContent = "保存失败：" + ((err && err.message) || err);
            $("ai-save").disabled = false;
        });
    }

    init();
})();
