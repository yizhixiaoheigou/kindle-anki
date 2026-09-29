/*
 * Browser port of the desktop converter pipeline (tools/kindle_anki_importer.py
 * + kindle_apkg.py + kindle_cards.py + kindle_bundle.py). The conversion runs
 * entirely inside the visitor's browser; the Kindle plugin never unpacks Anki
 * files, it only receives the finished kindle-anki zip produced here.
 *
 * The port mirrors the Python behaviour card for card so the same .apkg
 * converts to the same pack JSON on both paths; tests/test_kindle_web_converter.py
 * pins this against the Python importer.
 */
(function (root, factory) {
    "use strict";
    var apkg = (typeof module !== "undefined" && module.exports)
        ? require("./apkg.js")
        : root.KindleApkg;
    var api = factory(apkg);
    if (typeof module !== "undefined" && module.exports) {
        module.exports = api;
    } else {
        root.KindleAnkiConvert = api;
    }
})(typeof self !== "undefined" ? self : this, function (K) {
    "use strict";

    var FORMAT_NAME = "kindle-anki";
    var FORMAT_VERSION = 1;
    var PACK_SUFFIX = ".kindle-anki.json";
    var ZIP_SUFFIX = ".kindle-anki.zip";
    var MEDIA_SUFFIX = ".kindle-anki.media";
    var MAX_OPTIONS = 64;
    var MAX_CARDS = 100000;
    var MAX_IMAGES_PER_CARD = 8;
    var LEGACY_EXPORT_HINT =
        'Re-export from Anki with "Support older Anki versions" enabled.';

    function AnkiError(message) {
        var error = new Error(message);
        error.name = "AnkiError";
        return error;
    }
    function PackageError(message) {
        var error = new Error(message);
        error.name = "KindlePackageError";
        return error;
    }

    // ------------------------------------------------------------------
    // Character references (html.unescape subset)
    // ------------------------------------------------------------------

    var ENTITIES = {
        amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: "\u00a0",
        iexcl: "\u00a1", cent: "\u00a2", pound: "\u00a3", curren: "\u00a4",
        yen: "\u00a5", brvbar: "\u00a6", sect: "\u00a7", uml: "\u00a8",
        copy: "\u00a9", ordf: "\u00aa", laquo: "\u00ab", not: "\u00ac",
        shy: "\u00ad", reg: "\u00ae", macr: "\u00af", deg: "\u00b0",
        plusmn: "\u00b1", sup2: "\u00b2", sup3: "\u00b3", acute: "\u00b4",
        micro: "\u00b5", para: "\u00b6", middot: "\u00b7", cedil: "\u00b8",
        sup1: "\u00b9", ordm: "\u00ba", raquo: "\u00bb", frac14: "\u00bc",
        frac12: "\u00bd", frac34: "\u00be", iquest: "\u00bf",
        Agrave: "\u00c0", Aacute: "\u00c1", Acirc: "\u00c2", Atilde: "\u00c3",
        Auml: "\u00c4", Aring: "\u00c5", AElig: "\u00c6", Ccedil: "\u00c7",
        Egrave: "\u00c8", Eacute: "\u00c9", Ecirc: "\u00ca", Euml: "\u00cb",
        Igrave: "\u00cc", Iacute: "\u00cd", Icirc: "\u00ce", Iuml: "\u00cf",
        ETH: "\u00d0", Ntilde: "\u00d1", Ograve: "\u00d2", Oacute: "\u00d3",
        Ocirc: "\u00d4", Otilde: "\u00d5", Ouml: "\u00d6", times: "\u00d7",
        Oslash: "\u00d8", Ugrave: "\u00d9", Uacute: "\u00da", Ucirc: "\u00db",
        Uuml: "\u00dc", Yacute: "\u00dd", THORN: "\u00de", szlig: "\u00df",
        agrave: "\u00e0", aacute: "\u00e1", acirc: "\u00e2", atilde: "\u00e3",
        auml: "\u00e4", aring: "\u00e5", aelig: "\u00e6", ccedil: "\u00e7",
        egrave: "\u00e8", eacute: "\u00e9", ecirc: "\u00ea", euml: "\u00eb",
        igrave: "\u00ec", iacute: "\u00ed", icirc: "\u00ee", iuml: "\u00ef",
        eth: "\u00f0", ntilde: "\u00f1", ograve: "\u00f2", oacute: "\u00f3",
        ocirc: "\u00f4", otilde: "\u00f5", ouml: "\u00f6", divide: "\u00f7",
        oslash: "\u00f8", ugrave: "\u00f9", uacute: "\u00fa", ucirc: "\u00fb",
        uuml: "\u00fc", yacute: "\u00fd", thorn: "\u00fe", yuml: "\u00ff",
        OElig: "\u0152", oelig: "\u0153", Scaron: "\u0160", scaron: "\u0161",
        Yuml: "\u0178", fnof: "\u0192", circ: "\u02c6", tilde: "\u02dc",
        ensp: "\u2002", emsp: "\u2003", thinsp: "\u2009", zwnj: "\u200c",
        zwj: "\u200d", lrm: "\u200e", rlm: "\u200f", ndash: "\u2013",
        mdash: "\u2014", lsquo: "\u2018", rsquo: "\u2019", sbquo: "\u201a",
        ldquo: "\u201c", rdquo: "\u201d", bdquo: "\u201e", dagger: "\u2020",
        Dagger: "\u2021", bull: "\u2022", hellip: "\u2026", permil: "\u2030",
        prime: "\u2032", Prime: "\u2033", lsaquo: "\u2039", rsaquo: "\u203a",
        oline: "\u203e", frasl: "\u2044", euro: "\u20ac", image: "\u2111",
        weierp: "\u2118", real: "\u211c", trade: "\u2122", alefsym: "\u2135",
        larr: "\u2190", uarr: "\u2191", rarr: "\u2192", darr: "\u2193",
        harr: "\u2194", crarr: "\u21b5", lArr: "\u21d0", uArr: "\u21d1",
        rArr: "\u21d2", dArr: "\u21d3", hArr: "\u21d4", forall: "\u2200",
        part: "\u2202", exist: "\u2203", empty: "\u2205", nabla: "\u2207",
        isin: "\u2208", notin: "\u2209", ni: "\u220b", prod: "\u220f",
        sum: "\u2211", minus: "\u2212", lowast: "\u2217", radic: "\u221a",
        prop: "\u221d", infin: "\u221e", ang: "\u2220", and: "\u2227",
        or: "\u2228", cap: "\u2229", cup: "\u222a", int: "\u222b",
        there4: "\u2234", sim: "\u223c", cong: "\u2245", asymp: "\u2248",
        ne: "\u2260", equiv: "\u2261", le: "\u2264", ge: "\u2265",
        sub: "\u2282", sup: "\u2283", nsub: "\u2284", sube: "\u2286",
        supe: "\u2287", oplus: "\u2295", otimes: "\u2297", perp: "\u22a5",
        sdot: "\u22c5", lceil: "\u2308", rceil: "\u2309", lfloor: "\u230a",
        rfloor: "\u230b", lang: "\u2329", rang: "\u232a", loz: "\u25ca",
        spades: "\u2660", clubs: "\u2663", hearts: "\u2665", diams: "\u2666",
        alpha: "\u03b1", beta: "\u03b2", gamma: "\u03b3", delta: "\u03b4",
        epsilon: "\u03b5", zeta: "\u03b6", eta: "\u03b7", theta: "\u03b8",
        iota: "\u03b9", kappa: "\u03ba", lambda: "\u03bb", mu: "\u03bc",
        nu: "\u03bd", xi: "\u03be", omicron: "\u03bf", pi: "\u03c0",
        rho: "\u03c1", sigmaf: "\u03c2", sigma: "\u03c3", tau: "\u03c4",
        upsilon: "\u03c5", phi: "\u03c6", chi: "\u03c7", psi: "\u03c8",
        omega: "\u03c9", Alpha: "\u0391", Beta: "\u0392", Gamma: "\u0393",
        Delta: "\u0394", Theta: "\u0398", Lambda: "\u039b", Pi: "\u03a0",
        Sigma: "\u03a3", Phi: "\u03a6", Psi: "\u03a8", Omega: "\u03a9",
    };

    function decodeEntities(value) {
        return value.replace(/&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/g,
            function (whole, body) {
                if (body.charAt(0) === "#") {
                    var code = body.charAt(1) === "x" || body.charAt(1) === "X"
                        ? parseInt(body.slice(2), 16)
                        : parseInt(body.slice(1), 10);
                    if (!isFinite(code) || code < 0 || code > 0x10FFFF) {
                        return "\uFFFD";
                    }
                    try {
                        return String.fromCodePoint(code);
                    } catch (range) {
                        return "\uFFFD";
                    }
                }
                return body in ENTITIES ? ENTITIES[body] : whole;
            });
    }

    // ------------------------------------------------------------------
    // HTML -> plain text (port of the Python HTMLParser extractor)
    // ------------------------------------------------------------------

    var BLOCK_TAGS = {};
    "address article aside blockquote div dl fieldset footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section table td th tr ul"
        .split(" ").forEach(function (tag) { BLOCK_TAGS[tag] = true; });

    function tagEnd(source, start) {
        // Returns [indexAfterGt, selfClosing], honouring quoted attributes.
        var quote = null;
        for (var i = start; i < source.length; i++) {
            var ch = source.charAt(i);
            if (quote) {
                if (ch === quote) quote = null;
            } else if (ch === "\"" || ch === "'") {
                quote = ch;
            } else if (ch === ">") {
                return [i + 1, source.charAt(i - 1) === "/"];
            }
        }
        return [source.length, false];
    }

    var TAG_NAME = /^<\/?([a-zA-Z][^\s/>]*)/;

    function extractTextParts(value) {
        var parts = [];
        var index = 0;
        while (index < value.length) {
            var next = value.indexOf("<", index);
            if (next < 0) {
                parts.push(decodeEntities(value.slice(index)));
                break;
            }
            if (next > index) {
                parts.push(decodeEntities(value.slice(index, next)));
            }
            if (value.startsWith("<!--", next)) {
                var commentEnd = value.indexOf("-->", next + 4);
                index = commentEnd < 0 ? value.length : commentEnd + 3;
                continue;
            }
            if (value.startsWith("<!", next) || value.startsWith("<?", next)) {
                var declEnd = value.indexOf(">", next);
                index = declEnd < 0 ? value.length : declEnd + 1;
                continue;
            }
            var name = TAG_NAME.exec(value.slice(next, next + 40));
            if (!name) {
                parts.push("<");
                index = next + 1;
                continue;
            }
            var tag = name[1].toLowerCase();
            var end = tagEnd(value, next);
            var selfClosing = end[1];
            if (tag === "br" || BLOCK_TAGS[tag]) {
                parts.push("\n");
            }
            index = end[0];
        }
        return parts;
    }

    function htmlToText(value) {
        var text = extractTextParts(value).join("")
            .replace(/\r\n/g, "\n").replace(/\r/g, "\n");
        var lines = text.split("\n").map(function (line) {
            return line.split(/\s+/).filter(Boolean).join(" ");
        });
        var compact = [];
        for (var i = 0; i < lines.length; i++) {
            if (lines[i] || (compact.length && compact[compact.length - 1])) {
                compact.push(lines[i]);
            }
        }
        return compact.join("\n").trim();
    }

    var UNSUPPORTED_MARKUP = /<\s*(?:script|style|math|canvas)\b|\{\{\s*cloze\s*:|\{\{\s*c\d+\s*::/i;
    var MEDIA_MARKUP = /<\s*(?:img|audio|video|iframe|object|embed|svg)\b[^>]*>/gi;
    var MEDIA_SHORTCODE = /\[(?:sound|ankiimage):[^\]]*\]?/gi;
    // Non-global copies for .test(), whose g-flag siblings carry lastIndex.
    var MEDIA_MARKUP_TEST = /<\s*(?:img|audio|video|iframe|object|embed|svg)\b[^>]*>/i;
    var MEDIA_SHORTCODE_TEST = /\[(?:sound|ankiimage):[^\]]*\]?/i;
    var IMAGE_SRC = /<\s*img\b[^>]*\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))/gi;
    var IMAGE_SHORTCODE = /\[ankiimage:([^\]]+)\]/gi;
    var EMBEDDED_OPTION = /^\s*([A-Z])\s*[\.．、:：]\s*(.+?)\s*$/gm;
    var ANSWER_LABELS = /^\s*([A-Z](?:\s*[,，、/]\s*[A-Z])*)\s*[\.．、:：]?\s*(?:\s|$)/;

    function cardText(value) {
        if (UNSUPPORTED_MARKUP.test(value)) {
            return [null, "unsupported_markup"];
        }
        return [htmlToText(value), null];
    }

    function clean(value) {
        value = String(value == null ? "" : value);
        value = value.replace(MEDIA_MARKUP, " ").replace(MEDIA_SHORTCODE, " ");
        var result = cardText(value);
        return result[1] ? null : result[0];
    }

    function hasMedia(value) {
        return MEDIA_MARKUP_TEST.test(value) || MEDIA_SHORTCODE_TEST.test(value);
    }

    // ------------------------------------------------------------------
    // Name helpers
    // ------------------------------------------------------------------

    function nameKey(value) {
        return String(value).toLowerCase().replace(/[\s_-]+/g, "");
    }

    function optionOrder(value) {
        var normalized = nameKey(value);
        var numeric = /^(?:option|choice|select|选项)(\d+)$/.exec(normalized);
        if (numeric) {
            return parseInt(numeric[1], 10);
        }
        var letter = /^(?:option|choice|select|选项)([a-z])$/.exec(normalized);
        if (letter) {
            return letter[1].toUpperCase().charCodeAt(0) - 64;
        }
        if (/^[a-z]$/.test(normalized)) {
            return normalized.toUpperCase().charCodeAt(0) - 64;
        }
        return null;
    }

    function findIndex(indexes, names) {
        for (var i = 0; i < names.length; i++) {
            var key = nameKey(names[i]);
            if (key in indexes) {
                return indexes[key];
            }
        }
        return null;
    }

    function parseMappingIndexes(value, fieldCount, label) {
        if (value == null) {
            return [];
        }
        if (!Array.isArray(value)) {
            throw AnkiError(label + " must be a list of field indexes");
        }
        var indexes = [];
        for (var i = 0; i < value.length; i++) {
            var index = typeof value[i] === "number" ? Math.trunc(value[i])
                : /^-?\d+$/.test(String(value[i]).trim()) ? parseInt(value[i], 10)
                : NaN;
            if (!isFinite(index)) {
                throw AnkiError(label + " contains a non-integer field index");
            }
            if (index < 0 || index >= fieldCount) {
                throw AnkiError(label + " field index " + index + " is out of range");
            }
            indexes.push(index);
        }
        return indexes;
    }

    function extractField(fields, index) {
        return index >= 0 && index < fields.length ? fields[index] : "";
    }

    function field(fields, index) {
        return extractField(fields, index == null ? -1 : index);
    }

    function joinedText(fields, indexes) {
        var parts = [];
        for (var i = 0; i < indexes.length; i++) {
            var part = clean(field(fields, indexes[i]));
            if (part) {
                parts.push(part);
            }
        }
        return parts.join("\n");
    }

    function joinedRaw(fields, indexes) {
        var parts = [];
        for (var i = 0; i < indexes.length; i++) {
            parts.push(field(fields, indexes[i]));
        }
        return parts.join("");
    }

    function parseTags(rawTags) {
        return String(rawTags == null ? "" : rawTags).split(/\s+/).filter(Boolean);
    }

    function deckName(decks, deckId) {
        var raw = decks[String(deckId)];
        if (!raw) {
            return null;
        }
        var name = raw.name;
        return name ? String(name) : null;
    }

    // ------------------------------------------------------------------
    // Note-type detection (port of _models)
    // ------------------------------------------------------------------

    function detectModels(rawModels, fieldMapping) {
        if (!rawModels || rawModels.trim() === "" || rawModels.trim() === "{}") {
            throw AnkiError(
                "this export uses the newer Anki format (schema 18+), which is not " +
                "supported by this first importer yet. Re-export with Anki's older " +
                "format compatibility option.");
        }
        var raw;
        try {
            raw = JSON.parse(rawModels);
        } catch (error) {
            throw AnkiError("collection models JSON is invalid: " + error.message);
        }
        if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
            throw AnkiError("collection models are not a note-type table");
        }

        var mapping = fieldMapping || {};
        var supported = {};
        var unsupported = [];
        var modelIds = Object.keys(raw);
        for (var m = 0; m < modelIds.length; m++) {
            var model = raw[modelIds[m]];
            if (model === null || typeof model !== "object" || Array.isArray(model)) {
                unsupported.push("Unnamed: malformed_note_type");
                continue;
            }
            var name = String(model.name == null ? "Unnamed" : model.name);
            var modelId;
            try {
                modelId = strictInt(model.id);
            } catch (idError) {
                unsupported.push(name + ": malformed_id");
                continue;
            }
            var fields = model.flds || [];
            if (!Array.isArray(fields)) {
                unsupported.push(name + ": malformed_fields");
                continue;
            }
            var indexes = Object.create(null);
            var names = [];
            for (var f = 0; f < fields.length; f++) {
                var entry = fields[f];
                if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
                    continue;
                }
                var fieldName = String(entry.name == null ? "" : entry.name);
                indexes[nameKey(fieldName)] = f;
                names.push(fieldName);
            }
            var optionPairs = [];
            for (var n = 0; n < names.length; n++) {
                var order = optionOrder(names[n]);
                if (order !== null) {
                    optionPairs.push([order, n]);
                }
            }
            optionPairs.sort(function (a, b) { return a[0] - b[0]; });
            var optionIndexes = optionPairs.map(function (pair) { return pair[1]; });
            var questionIndex = findIndex(indexes, ["question", "front", "prompt", "题目", "问题"]);
            var correctIndex = findIndex(indexes,
                ["correct", "correct answer", "answer", "答案", "正确选项", "正确答案"]);
            var explanationIndex = findIndex(indexes,
                ["explanation", "解析", "notes", "back", "说明", "answer explanation"]);
            var packedOptionsIndex = findIndex(indexes,
                ["options", "选项", "choices", "optionlist"]);
            var nameHint = name.toLowerCase();
            var forcedMultiple = ["multiple", "multi", "多选"].some(function (token) {
                return nameHint.indexOf(token) >= 0;
            });
            var detected = null;
            var reason = null;
            if (optionIndexes.length > 64) {
                reason = name + ": too_many_options";
            } else if (optionIndexes.length >= 2 && questionIndex !== null && correctIndex !== null) {
                detected = {
                    modelId: modelId, name: name, kind: "choice",
                    questionIndex: questionIndex, optionIndexes: optionIndexes,
                    packedOptionsIndex: null, correctIndex: correctIndex,
                    explanationIndex: explanationIndex, forcedMultiple: forcedMultiple,
                    frontIndexes: [questionIndex],
                    backIndexes: explanationIndex !== null ? [explanationIndex] : [],
                };
            } else if (packedOptionsIndex !== null && questionIndex !== null && correctIndex !== null) {
                detected = {
                    modelId: modelId, name: name, kind: "choice",
                    questionIndex: questionIndex, optionIndexes: [],
                    packedOptionsIndex: packedOptionsIndex, correctIndex: correctIndex,
                    explanationIndex: explanationIndex, forcedMultiple: forcedMultiple,
                    frontIndexes: [questionIndex],
                    backIndexes: explanationIndex !== null ? [explanationIndex] : [],
                };
            } else {
                var frontIndex = findIndex(indexes,
                    ["front", "question", "prompt", "正面", "前面", "题目", "问题"]);
                var backIndex = findIndex(indexes,
                    ["back", "answer", "背面", "后面", "答案", "response", "解析"]);
                if (frontIndex !== null && backIndex !== null) {
                    detected = {
                        modelId: modelId, name: name, kind: "short_answer",
                        frontIndex: frontIndex, backIndex: backIndex,
                        optionIndexes: [], packedOptionsIndex: null,
                        correctIndex: null, explanationIndex: null,
                        forcedMultiple: false,
                        frontIndexes: [frontIndex], backIndexes: [backIndex],
                    };
                } else {
                    reason = name + ": no_supported_card_shape";
                }
            }

            var spec = mapping[String(modelId)];
            if (spec !== null && spec !== undefined && typeof spec === "object" && !Array.isArray(spec)) {
                var mappedFront = parseMappingIndexes(spec.front, names.length, name + " front");
                var mappedBack = parseMappingIndexes(spec.back, names.length, name + " back");
                if (mappedFront.length) {
                    if (detected && detected.kind === "choice") {
                        detected = {
                            modelId: modelId, name: name, kind: "choice",
                            questionIndex: mappedFront[0],
                            optionIndexes: detected.optionIndexes,
                            packedOptionsIndex: detected.packedOptionsIndex,
                            correctIndex: detected.correctIndex,
                            explanationIndex: mappedBack.length ? mappedBack[0] : detected.explanationIndex,
                            forcedMultiple: detected.forcedMultiple,
                            frontIndexes: mappedFront, backIndexes: mappedBack,
                        };
                    } else {
                        detected = {
                            modelId: modelId, name: name, kind: "short_answer",
                            frontIndex: mappedFront[0],
                            backIndex: mappedBack.length ? mappedBack[0] : null,
                            optionIndexes: [], packedOptionsIndex: null,
                            correctIndex: null, explanationIndex: null,
                            forcedMultiple: false,
                            frontIndexes: mappedFront, backIndexes: mappedBack,
                        };
                    }
                }
            }
            if (detected) {
                supported[modelId] = detected;
            } else if (reason) {
                unsupported.push(reason);
            }
        }
        return [supported, unsupported];
    }

    function strictInt(value) {
        if (typeof value === "boolean") {
            return value ? 1 : 0;
        }
        if (typeof value === "number" && isFinite(value)) {
            return Math.trunc(value);
        }
        if (typeof value === "string" && /^[-+]?\d+$/.test(value.trim())) {
            return parseInt(value, 10);
        }
        throw new TypeError("not an integer");
    }

    // ------------------------------------------------------------------
    // Media
    // ------------------------------------------------------------------

    function safeMediaName(value) {
        var name = String(value).split("/").pop().split("\\").pop();
        name = name.replace(/[^A-Za-z0-9._-]+/g, "_");
        return name || "image";
    }

    function splitName(name) {
        var dot = name.lastIndexOf(".");
        if (dot <= 0) {
            return { stem: name, suffix: "" };
        }
        return { stem: name.slice(0, dot), suffix: name.slice(dot) };
    }

    function sniffDimensions(data) {
        return K.imageDimensions(data) || { width: 600, height: 400 };
    }

    function ApkgArchive(fileBytes, fileName) {
        if (String(fileName || "").slice(-5).toLowerCase() !== ".apkg") {
            throw AnkiError("the Kindle importer accepts an .apkg file");
        }
        this.fileName = fileName;
        this._mediaCatalog = null;
        try {
            this.zip = new K.ZipReader(fileBytes);
        } catch (error) {
            throw AnkiError("cannot open " + fileName + ": " + error.message);
        }
    }

    ApkgArchive.prototype.collectionName = function () {
        if (this.zip.has("collection.anki21")) {
            return "collection.anki21";
        }
        if (this.zip.has("collection.anki2")) {
            return "collection.anki2";
        }
        if (this.zip.has("collection.anki21b")) {
            throw AnkiError(
                "cannot decompress collection.anki21b; " +
                "export an .apkg compatible with collection.anki21. " + LEGACY_EXPORT_HINT);
        }
        throw AnkiError(".apkg has no collection.anki21 or collection.anki2");
    };

    ApkgArchive.prototype.readCollection = function () {
        var self = this;
        return this.zip.read(this.collectionName()).then(function (bytes) {
            try {
                return new K.SQLite(bytes);
            } catch (error) {
                throw AnkiError("cannot read Anki collection tables: " + error.message);
            }
        });
    };

    ApkgArchive.prototype.mediaCatalog = function () {
        if (this._mediaCatalog) {
            return this._mediaCatalog;
        }
        this._mediaCatalog = this.zip.read("media").then(function (bytes) {
            var raw;
            try {
                raw = JSON.parse(new TextDecoder("utf-8").decode(bytes));
            } catch (error) {
                return {};
            }
            if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
                return {};
            }
            return raw;
        }).catch(function () {
            return {};
        }).then(function (raw) {
            var entries = [];
            Object.keys(raw).forEach(function (archiveName) {
                entries.push([archiveName, decodeEntities(String(raw[archiveName]))]);
            });
            return entries;
        });
        // Filter to entries that really exist in the archive, then allocate
        // unique output names against the full set up front so a deduplicated
        // name can never collide with a later real name.
        var self = this;
        return this._mediaCatalog.then(function (entries) {
            var present = [];
            var taken = {};
            entries.forEach(function (entry) {
                if (self.zip.has(entry[0])) {
                    present.push(entry);
                }
            });
            var finalNames = present.map(function (entry) {
                var base = safeMediaName(entry[1]);
                var candidate = base;
                var counter = 1;
                while (candidate in taken) {
                    counter += 1;
                    var parts = splitName(base);
                    candidate = parts.stem + "_" + counter + parts.suffix;
                }
                taken[candidate] = true;
                return candidate;
            });
            var catalog = {};
            var reads = [];
            for (var i = 0; i < present.length; i++) {
                (function (index) {
                    reads.push(self.zip.read(present[index][0]).then(function (data) {
                        var dimensions = sniffDimensions(data);
                        catalog[present[index][1]] = {
                            archiveName: present[index][0],
                            name: finalNames[index],
                            width: dimensions.width,
                            height: dimensions.height,
                        };
                    }).catch(function () { }));
                })(i);
            }
            return Promise.all(reads).then(function () { return catalog; });
        });
    };

    function imageRefs(value, catalog) {
        var names = [];
        var match;
        IMAGE_SRC.lastIndex = 0;
        while ((match = IMAGE_SRC.exec(value)) !== null) {
            names.push(match[1] != null ? match[1] : match[2] != null ? match[2] : match[3]);
        }
        IMAGE_SHORTCODE.lastIndex = 0;
        while ((match = IMAGE_SHORTCODE.exec(value)) !== null) {
            names.push(match[1]);
        }
        var result = [];
        var seen = {};
        for (var i = 0; i < names.length; i++) {
            var sourceName = decodeEntities(names[i]).trim();
            var base = sourceName.split("/").pop().split("\\").pop();
            var asset = catalog[sourceName] || catalog[base];
            if (!asset || asset.name in seen) {
                continue;
            }
            seen[asset.name] = true;
            result.push({ name: asset.name, width: asset.width, height: asset.height });
        }
        return result;
    }

    // ------------------------------------------------------------------
    // Choice answers
    // ------------------------------------------------------------------

    function optionLabel(index) {
        var label = "";
        index += 1;
        while (index > 0) {
            var remainder = (index - 1) % 26;
            label = String.fromCharCode(65 + remainder) + label;
            index = Math.floor((index - 1) / 26);
        }
        return label;
    }

    function correctIndices(raw, options) {
        var value = String(raw == null ? "" : raw).replace(/<[^>]+>/g, " ").trim();
        var upper = value.toUpperCase();

        var optionByText = {};
        for (var o = 0; o < options.length; o++) {
            optionByText[options[o].replace(/\s+/g, "").toLowerCase()] = o;
        }
        var tokens = value.split(/[,，;；/、\s]+/).filter(Boolean);
        var tokenMatches = [];
        for (var t = 0; t < tokens.length; t++) {
            var key = tokens[t].replace(/\s+/g, "").toLowerCase();
            if (key in optionByText) {
                tokenMatches.push(optionByText[key]);
            }
        }
        if (tokenMatches.length && tokenMatches.length === tokens.length) {
            return sortedUnique(tokenMatches);
        }

        var found = [];
        var condensed = upper.replace(/ /g, "");
        for (var i = 0; i < options.length; i++) {
            var letter = String.fromCharCode(65 + i);
            var bounded = new RegExp("(?:^|[^A-Z])" + letter + "(?:$|[^A-Z])").test(upper);
            if (bounded || (/^[A-Z]+$/.test(condensed) && condensed.indexOf(letter) >= 0)) {
                found.push(i);
            }
        }
        if (found.length) {
            return sortedUnique(found);
        }

        var numbers = value.match(/\d+/g);
        if (numbers && numbers.length &&
            numbers.every(function (number) {
                var parsed = parseInt(number, 10);
                return parsed >= 1 && parsed <= options.length;
            })) {
            return sortedUnique(numbers.map(function (number) { return parseInt(number, 10) - 1; }));
        }
        var normalized = value.replace(/\s+/g, "").toLowerCase();
        for (var n = 0; n < options.length; n++) {
            if (normalized === options[n].replace(/\s+/g, "").toLowerCase()) {
                return [n];
            }
        }
        return [];
    }

    function sortedUnique(values) {
        return Array.from(new Set(values)).sort(function (a, b) { return a - b; });
    }

    function packedOptions(raw) {
        var text = String(raw == null ? "" : raw).replace(/<br\s*\/?>/gi, "\n");
        var parts = text.split(/\|\|/).map(function (part) { return part.trim(); })
            .filter(Boolean);
        var options = [];
        for (var i = 0; i < parts.length; i++) {
            var item = clean(parts[i]);
            if (item) {
                options.push(item);
            }
        }
        return options;
    }

    function formatChoiceAnswer(raw, options) {
        var indices = correctIndices(raw, options);
        if (!indices.length) {
            return clean(raw) || "";
        }
        return indices.map(function (index) {
            return optionLabel(index) + ". " + options[index];
        }).join("、");
    }

    function embeddedChoice(front, back) {
        var matches = [];
        var match;
        EMBEDDED_OPTION.lastIndex = 0;
        while ((match = EMBEDDED_OPTION.exec(front)) !== null) {
            matches.push(match);
        }
        if (matches.length < 2 || matches[0][1] !== "A") {
            return null;
        }
        var labels = matches.map(function (item) { return item[1]; });
        for (var i = 0; i < labels.length; i++) {
            if (labels[i] !== String.fromCharCode(65 + i)) {
                return null;
            }
        }
        var question = front.slice(0, matches[0].index).trim();
        var options = matches.map(function (item) { return item[2].trim(); });
        if (!question || options.some(function (option) { return !option; })) {
            return null;
        }
        var answerMatch = ANSWER_LABELS.exec(back);
        if (!answerMatch) {
            return null;
        }
        var answerLabels = (answerMatch[1].toUpperCase().match(/[A-Z]/g)) || [];
        var correct = answerLabels.map(function (label) { return label.charCodeAt(0) - 65; });
        if (!correct.length || correct.some(function (index) { return index >= options.length; })) {
            return null;
        }
        return [question, options, sortedUnique(correct)];
    }

    // ------------------------------------------------------------------
    // Collection reading
    // ------------------------------------------------------------------

    function collectRows(database) {
        var cards = database.table("cards");
        if (!cards) {
            throw AnkiError("cannot read Anki collection tables: missing cards table");
        }
        var notes = database.table("notes");
        var noteById = {};
        if (notes) {
            notes.rows.forEach(function (note) {
                noteById[note.id] = note;
            });
        }
        var hasOdid = cards.columns.indexOf("odid") >= 0;
        var rows = cards.rows.map(function (card) {
            var note = card.nid != null ? noteById[card.nid] : null;
            return {
                cardId: card.id,
                noteId: note ? note.id : null,
                deckId: card.did,
                originalDeckId: hasOdid ? card.odid : null,
                cardOrd: card.ord,
                modelId: note ? note.mid : null,
                tags: note ? note.tags : null,
                fields: note ? note.flds : null,
            };
        });
        rows.sort(function (a, b) {
            return (a.deckId == null ? -1 : a.deckId) - (b.deckId == null ? -1 : b.deckId)
                || a.cardId - b.cardId;
        });
        return rows;
    }

    // ------------------------------------------------------------------
    // inspect / import
    // ------------------------------------------------------------------

    function readCollectionJson(database) {
        var col = database.table("col");
        if (!col) {
            throw AnkiError("collection database is missing the col table: missing col table");
        }
        var row = col.rows[0];
        if (!row) {
            throw AnkiError("collection database has no col row");
        }
        var models;
        try {
            models = JSON.parse(row.models);
        } catch (error) {
            models = undefined;
        }
        var decks;
        try {
            decks = JSON.parse(row.decks);
        } catch (error) {
            decks = undefined;
        }
        return { modelsText: row.models, decks: decks, decksError: decks === undefined };
    }

    function ApkgInspector(archive) {
        this.archive = archive;
    }

    ApkgInspector.prototype.read = function () {
        var self = this;
        return this.archive.readCollection().then(function (database) {
            var collection = readCollectionJson(database);
            var detected = detectModels(collection.modelsText, null);
            var supported = detected[0];
            var unsupported = detected[1];
            // inspect is deliberately lenient about a broken decks table;
            // importApkg is the one that refuses to continue on it.
            var decks = collection.decksError || collection.decks === null ||
                typeof collection.decks !== "object" || Array.isArray(collection.decks)
                ? {}
                : collection.decks;
            var samples = {};
            var notes = database.table("notes");
            if (notes) {
                notes.rows.forEach(function (note) {
                    if (note.mid == null) {
                        return;
                    }
                    if (!(note.mid in samples)) {
                        samples[note.mid] = String(note.flds == null ? "" : note.flds).split("\x1f");
                    }
                });
            }
            var cardDecks = {};
            var cards = database.table("cards");
            if (cards) {
                cards.rows.forEach(function (card) {
                    if (card.did != null) {
                        cardDecks[String(card.did)] = (cardDecks[String(card.did)] || 0) + 1;
                    }
                });
            }
            var models = [];
            var rawModels = collection.modelsText ? JSON.parse(collection.modelsText) : null;
            if (rawModels && typeof rawModels === "object" && !Array.isArray(rawModels)) {
                Object.keys(rawModels).forEach(function (key) {
                    var model = rawModels[key];
                    if (!model || typeof model !== "object" || Array.isArray(model)) {
                        return;
                    }
                    var modelId;
                    try {
                        modelId = strictInt(model.id);
                    } catch (error) {
                        return;
                    }
                    var fields = model.flds || [];
                    var names = [];
                    fields.forEach(function (entry) {
                        if (entry && typeof entry === "object" && !Array.isArray(entry)) {
                            names.push(String(entry.name == null ? "" : entry.name));
                        }
                    });
                    var detectedModel = supported[modelId];
                    var suggestedFront = detectedModel ? detectedModel.frontIndexes.slice()
                        : (names.length ? [0] : []);
                    var suggestedBack = detectedModel ? detectedModel.backIndexes.slice()
                        : (names.length > 1 ? [names.length - 1] : []);
                    models.push({
                        id: modelId,
                        name: String(model.name == null ? "Unnamed" : model.name),
                        fields: names,
                        kind: detectedModel ? detectedModel.kind : "unknown",
                        suggested_front: suggestedFront,
                        suggested_back: suggestedBack,
                        sample: samples[modelId] || [],
                    });
                });
            }
            var deckNames = {};
            if (decks && typeof decks === "object" && !Array.isArray(decks)) {
                Object.keys(decks).forEach(function (deckId) {
                    var rawDeck = decks[deckId];
                    if (rawDeck && typeof rawDeck === "object" && !Array.isArray(rawDeck)) {
                        deckNames[deckId] = String(rawDeck.name || ("Deck " + deckId));
                    }
                });
            }
            var ranked = Object.keys(deckNames).sort(function (a, b) {
                return (cardDecks[b] || 0) - (cardDecks[a] || 0) || (deckNames[a] < deckNames[b] ? -1 : deckNames[a] > deckNames[b] ? 1 : 0);
            });
            var stem = self.archive.fileName.replace(/\.[^.]*$/, "");
            return {
                title: stem,
                file_name: self.archive.fileName,
                deck_names: ranked.map(function (deckId) { return deckNames[deckId]; }),
                suggested_title: ranked.length && Object.keys(cardDecks).length ? deckNames[ranked[0]] : "",
                models: models,
                unsupported_models: unsupported.slice().sort(),
            };
        });
    };

    function primaryDeckTitle(deckNames, deckCards) {
        var ids = Array.from(deckNames.keys());
        if (!ids.length) {
            return "";
        }
        ids.sort(function (a, b) {
            return (deckCards.get(b) || []).length - (deckCards.get(a) || []).length
                || (a < b ? -1 : a > b ? 1 : 0);
        });
        return deckNames.get(ids[0]);
    }

    function importFromDatabase(archive, database, options) {
        options = options || {};
        var ai = options.ai || {};
        var fieldMapping = options.fieldMapping || null;
        var title = options.title;

        var collection = readCollectionJson(database);
        if (collection.decksError) {
            throw AnkiError("collection decks JSON is invalid: invalid JSON");
        }
        if (collection.decks === null || typeof collection.decks !== "object" || Array.isArray(collection.decks)) {
            throw AnkiError("collection decks are not an object");
        }
        var decks = collection.decks;
        var detected = detectModels(collection.modelsText, fieldMapping);
        var supported = detected[0];
        var unsupported = detected[1];

        return archive.mediaCatalog().then(function (mediaCatalog) {
            var rows = collectRows(database);

            var skipped = {};
            function bump(reason) {
                skipped[reason] = (skipped[reason] || 0) + 1;
            }
            var cards = [];
            var mediaCards = 0;
            var mediaFiles = {};
            var deckNames = new Map();
            var deckCards = new Map();
            var deckMap = new Map();
            for (var r = 0; r < rows.length; r++) {
                var row = rows[r];
                var model = row.modelId != null ? supported[row.modelId] : undefined;
                if (!model) {
                    bump("unsupported_model");
                    continue;
                }
                if ((row.cardOrd || 0) !== 0) {
                    bump("non_primary_template");
                    continue;
                }
                var sourceDeck = row.originalDeckId || row.deckId;
                if (sourceDeck == null || deckName(decks, sourceDeck) === null) {
                    bump("missing_deck");
                    continue;
                }
                var fields = String(row.fields == null ? "" : row.fields).split("\x1f");
                var cardHasMedia = false;
                var frontImages, backImages, front, back, cardFields;
                if (model.kind === "choice") {
                    var rawQuestion = joinedRaw(fields, model.frontIndexes);
                    var rawBack = joinedRaw(fields, model.backIndexes);
                    cardHasMedia = hasMedia(rawQuestion) || hasMedia(rawBack);
                    frontImages = imageRefs(rawQuestion, mediaCatalog);
                    backImages = imageRefs(rawBack, mediaCatalog);
                    front = joinedText(fields, model.frontIndexes);
                    var options;
                    if (model.packedOptionsIndex !== null) {
                        options = packedOptions(field(fields, model.packedOptionsIndex));
                    } else {
                        options = [];
                        for (var oi = 0; oi < model.optionIndexes.length; oi++) {
                            var option = clean(extractField(fields, model.optionIndexes[oi]));
                            if (option) {
                                options.push(option);
                            }
                        }
                    }
                    var correctRaw = field(fields, model.correctIndex);
                    var correct = correctIndices(correctRaw, options);
                    var backParts = [];
                    for (var bi = 0; bi < model.backIndexes.length; bi++) {
                        var index = model.backIndexes[bi];
                        var part;
                        if (model.correctIndex !== null && index === model.correctIndex) {
                            part = formatChoiceAnswer(field(fields, index), options);
                        } else {
                            part = clean(field(fields, index));
                        }
                        if (part) {
                            backParts.push(part);
                        }
                    }
                    back = backParts.join("\n");
                    if (!front) {
                        bump("empty_front");
                        continue;
                    }
                    if (options.length < 2) {
                        bump("not_enough_options");
                        continue;
                    }
                    if (!correct.length) {
                        bump("unreadable_correct_answer");
                        continue;
                    }
                    if (!back) {
                        back = "Correct option(s): " + correct.map(optionLabel).join(", ");
                    }
                    var mode = model.forcedMultiple || correct.length > 1 ? "multiple" : "single";
                    cardFields = {
                        type: "choice", mode: mode, front: front, back: back,
                        options: options, correct_indices: correct,
                    };
                } else {
                    var rawFront = joinedRaw(fields, model.frontIndexes);
                    var rawBack = joinedRaw(fields, model.backIndexes);
                    cardHasMedia = hasMedia(rawFront) || hasMedia(rawBack);
                    frontImages = imageRefs(rawFront, mediaCatalog);
                    backImages = imageRefs(rawBack, mediaCatalog);
                    front = joinedText(fields, model.frontIndexes);
                    back = joinedText(fields, model.backIndexes);
                    if (!front) {
                        bump("empty_front");
                        continue;
                    }
                    if (!back) {
                        bump("empty_back");
                        continue;
                    }
                    var embedded = embeddedChoice(front, back);
                    if (embedded) {
                        cardFields = {
                            type: "choice",
                            mode: embedded[2].length > 1 ? "multiple" : "single",
                            front: embedded[0], back: back,
                            options: embedded[1], correct_indices: embedded[2],
                        };
                    } else {
                        cardFields = { type: "short_answer", front: front, back: back };
                    }
                }

                if (frontImages.length) {
                    cardFields.front_images = frontImages;
                }
                if (backImages.length) {
                    cardFields.back_images = backImages;
                }

                var deviceDeckId;
                if (deckMap.has(sourceDeck)) {
                    deviceDeckId = deckMap.get(sourceDeck);
                } else {
                    deviceDeckId = deckMap.size + 1;
                    deckMap.set(sourceDeck, deviceDeckId);
                }
                var cardId = cards.length + 1;
                cards.push({
                    id: cardId,
                    source_card_id: row.cardId,
                    source_note_id: row.noteId,
                    deck_id: deviceDeckId,
                    tags: parseTags(row.tags),
                    type: cardFields.type,
                    mode: cardFields.mode,
                    front: cardFields.front,
                    back: cardFields.back,
                    options: cardFields.options,
                    correct_indices: cardFields.correct_indices,
                    expected_answers: cardFields.expected_answers,
                    front_images: cardFields.front_images,
                    back_images: cardFields.back_images,
                });
                if (cardHasMedia) {
                    mediaCards += 1;
                }
                frontImages.concat(backImages).forEach(function (image) {
                    mediaFiles[image.name] = true;
                });
                deckNames.set(deviceDeckId, deckName(decks, sourceDeck) || ("Deck " + sourceDeck));
                if (!deckCards.has(deviceDeckId)) {
                    deckCards.set(deviceDeckId, []);
                }
                deckCards.get(deviceDeckId).push(cardId);
            }

            if (!cards.length) {
                throw AnkiError(
                    "no importable cards in this .apkg (all notes were skipped or unsupported)");
            }
            var orderedDecks = Array.from(deckNames.keys()).sort(function (a, b) {
                var nameA = deckNames.get(a);
                var nameB = deckNames.get(b);
                return nameA < nameB ? -1 : nameA > nameB ? 1 : a - b;
            }).map(function (deckId) {
                return { id: deckId, name: deckNames.get(deckId), card_ids: deckCards.get(deckId) };
            });
            var packTitle = (title || "").trim()
                || primaryDeckTitle(deckNames, deckCards)
                || archive.fileName.replace(/\.[^.]*$/, "");
            var skippedKeys = Object.keys(skipped).sort();
            var skippedReasons = {};
            skippedKeys.forEach(function (key) { skippedReasons[key] = skipped[key]; });
            return {
                format: FORMAT_NAME,
                version: FORMAT_VERSION,
                title: packTitle,
                source: { type: "anki_apkg", file_name: archive.fileName },
                ai: ai,
                decks: orderedDecks,
                cards: cards,
                report: {
                    total_cards: rows.length,
                    imported_cards: cards.length,
                    skipped_cards: skippedKeys.reduce(function (sum, key) { return sum + skipped[key]; }, 0),
                    skipped_reasons: skippedReasons,
                    unsupported_models: unsupported.slice().sort(),
                    scheduling: "reset_to_new",
                    html_conversion: "plain_text",
                    media_cards: mediaCards,
                    media_files: Object.keys(mediaFiles).length,
                },
            };
        });
    }

    function importApkg(fileBytes, fileName, options) {
        var archive = new ApkgArchive(fileBytes, fileName);
        return archive.readCollection().then(function (database) {
            return importFromDatabase(archive, database, options);
        });
    }

    function inspectApkg(fileBytes, fileName) {
        var archive = new ApkgArchive(fileBytes, fileName);
        return new ApkgInspector(archive).read();
    }

    // ------------------------------------------------------------------
    // Pack validation (port of kindle_cards.validate_package)
    // ------------------------------------------------------------------

    function text(value, label, required) {
        if (typeof value !== "string") {
            if (value == null && !required) {
                return "";
            }
            throw PackageError(label + " must be text");
        }
        value = value.trim();
        if (required && !value) {
            throw PackageError(label + " must not be empty");
        }
        return value;
    }

    function positiveInt(value, label) {
        if (typeof value === "boolean") {
            throw PackageError(label + " must be an integer");
        }
        var number = typeof value === "number" ? value
            : /^[-+]?\d+$/.test(String(value).trim()) ? Number(String(value).trim())
            : NaN;
        if (!isFinite(number)) {
            throw PackageError(label + " must be an integer");
        }
        number = Math.trunc(number);
        if (number < 1) {
            throw PackageError(label + " must be positive");
        }
        return number;
    }

    function mediaRefs(raw, label) {
        if (raw == null) {
            return [];
        }
        if (!Array.isArray(raw) || raw.length > MAX_IMAGES_PER_CARD) {
            throw PackageError(label + " must contain at most " + MAX_IMAGES_PER_CARD + " images");
        }
        var result = [];
        for (var i = 0; i < raw.length; i++) {
            var item = raw[i];
            var index = i + 1;
            var name, width, height;
            if (typeof item === "string") {
                name = text(item, label + " image " + index, true);
                width = 600;
                height = 400;
            } else if (item && typeof item === "object" && !Array.isArray(item)) {
                name = text(item.name, label + " image " + index + " name", true);
                width = item.width == null ? 600 : positiveInt(item.width, label + " image " + index + " width");
                height = item.height == null ? 400 : positiveInt(item.height, label + " image " + index + " height");
            } else {
                throw PackageError(label + " image " + index + " must be an object");
            }
            if (name === "." || name === ".." || name.indexOf("/") >= 0 || name.indexOf("\\") >= 0) {
                throw PackageError(label + " image " + index + " name must be a plain filename");
            }
            result.push({ name: name, width: width, height: height });
        }
        return result;
    }

    function validateAi(raw) {
        if (raw == null) {
            return {};
        }
        if (typeof raw !== "object" || Array.isArray(raw)) {
            throw PackageError("ai must be an object");
        }
        var allowed = ["endpoint", "model", "system_prompt", "profile_id", "api_key"];
        var unknown = Object.keys(raw).filter(function (key) {
            return allowed.indexOf(key) < 0;
        }).sort();
        if (unknown.length) {
            throw PackageError(
                "ai has unsupported fields; use the canonical api_key field for credentials");
        }
        var result = {};
        allowed.forEach(function (field) {
            var value = raw[field];
            if (value != null) {
                result[field] = text(value, "ai." + field, true);
            }
        });
        if ("endpoint" in result &&
            result.endpoint.indexOf("http://") !== 0 && result.endpoint.indexOf("https://") !== 0) {
            throw PackageError("ai.endpoint must use http:// or https://");
        }
        return result;
    }

    function validatePackage(pack) {
        if (!pack || typeof pack !== "object" || Array.isArray(pack)) {
            throw PackageError("package must be an object");
        }
        if ((pack.format !== "kindle-anki" && pack.format !== "folo-kindle-anki") || pack.version !== 1) {
            throw PackageError(
                "unsupported Kindle pack format " + JSON.stringify(pack.format) +
                " version " + JSON.stringify(pack.version));
        }
        var title = text(pack.title == null ? "Untitled deck" : pack.title, "title", true);
        var mediaDir = pack.media_dir;
        if (mediaDir != null) {
            mediaDir = text(mediaDir, "media_dir", true);
            if (mediaDir.indexOf("/") >= 0 || mediaDir.indexOf("\\") >= 0 ||
                mediaDir === "." || mediaDir === "..") {
                throw PackageError("media_dir must be a relative directory name");
            }
        }
        var rawDecks = pack.decks;
        var rawCards = pack.cards;
        if (!Array.isArray(rawDecks) || !Array.isArray(rawCards)) {
            throw PackageError("package must contain decks and cards arrays");
        }
        if (rawCards.length > MAX_CARDS) {
            throw PackageError("package has more than " + MAX_CARDS + " cards");
        }

        var decks = [];
        var deckIds = {};
        rawDecks.forEach(function (rawDeck, index) {
            var number = index + 1;
            if (!rawDeck || typeof rawDeck !== "object" || Array.isArray(rawDeck)) {
                throw PackageError("deck " + number + " must be an object");
            }
            var deckId = positiveInt(rawDeck.id, "deck " + number + " id");
            if (deckId in deckIds) {
                throw PackageError("duplicate deck id " + deckId);
            }
            deckIds[deckId] = true;
            var cardIds = (rawDeck.card_ids || []).map(function (cardId) {
                if (typeof cardId === "number" && isFinite(cardId)) {
                    return Math.trunc(cardId);
                }
                throw PackageError("deck " + deckId + " card_ids must be integers");
            });
            decks.push({
                id: deckId,
                name: text(rawDeck.name == null ? "Deck " + deckId : rawDeck.name, "deck " + deckId + " name", true),
                card_ids: cardIds,
            });
        });

        var cards = [];
        var cardIdsSeen = {};
        rawCards.forEach(function (rawCard, index) {
            var number = index + 1;
            if (!rawCard || typeof rawCard !== "object" || Array.isArray(rawCard)) {
                throw PackageError("card " + number + " must be an object");
            }
            var cardId = positiveInt(rawCard.id, "card " + number + " id");
            var deckId = positiveInt(rawCard.deck_id, "card " + cardId + " deck_id");
            if (cardId in cardIdsSeen) {
                throw PackageError("duplicate card id " + cardId);
            }
            if (!(deckId in deckIds)) {
                throw PackageError("card " + cardId + " refers to unknown deck " + deckId);
            }
            cardIdsSeen[cardId] = true;

            var cardType = rawCard.type;
            if (cardType !== "short_answer" && cardType !== "choice") {
                throw PackageError("card " + cardId + " type must be one of choice, short_answer");
            }
            var card = {
                id: cardId,
                deck_id: deckId,
                type: cardType,
                front: text(rawCard.front, "card " + cardId + " front", true),
                back: text(rawCard.back, "card " + cardId + " back", true),
                tags: (rawCard.tags || []).map(function (tag) { return String(tag); }),
            };
            ["front_images", "back_images"].forEach(function (field) {
                var refs = mediaRefs(rawCard[field], "card " + cardId + " " + field);
                if (refs.length) {
                    card[field] = refs;
                }
            });
            if (cardType === "short_answer") {
                var expected = rawCard.expected_answers == null ? [] : rawCard.expected_answers;
                if (!Array.isArray(expected)) {
                    throw PackageError("card " + cardId + " expected_answers must be an array");
                }
                card.expected_answers = expected.map(function (answer) {
                    return text(answer, "card " + cardId + " expected answer", true);
                });
            } else {
                var mode = rawCard.mode;
                if (mode !== "single" && mode !== "multiple") {
                    throw PackageError("card " + cardId + " choice mode must be single or multiple");
                }
                var options = rawCard.options;
                if (!Array.isArray(options) || options.length < 2 || options.length > MAX_OPTIONS) {
                    throw PackageError("card " + cardId + " must have between 2 and " + MAX_OPTIONS + " options");
                }
                card.mode = mode;
                card.options = options.map(function (option, optionIndex) {
                    return text(option, "card " + cardId + " option " + (optionIndex + 1), true);
                });
                var correct = rawCard.correct_indices;
                if (!Array.isArray(correct) || !correct.length) {
                    throw PackageError("card " + cardId + " needs correct_indices");
                }
                var invalid = correct.some(function (index) {
                    return typeof index === "boolean" || !isFinite(index) ||
                        Math.trunc(index) !== index || index < 0 || index >= options.length;
                });
                if (invalid) {
                    throw PackageError("card " + cardId + " has an invalid correct index");
                }
                var unique = new Set(correct);
                if (unique.size !== correct.length) {
                    throw PackageError("card " + cardId + " has duplicate correct indices");
                }
                if (mode === "single" && correct.length !== 1) {
                    throw PackageError("card " + cardId + " single choice needs one correct index");
                }
                card.correct_indices = correct.slice();
            }
            ["source_card_id", "source_note_id"].forEach(function (field) {
                if (field in rawCard) {
                    card[field] = rawCard[field];
                }
            });
            cards.push(card);
        });

        var ai = validateAi(pack.ai);
        var normalizedDecks = decks.map(function (deck) {
            return {
                id: deck.id,
                name: deck.name,
                card_ids: cards.filter(function (card) { return card.deck_id === deck.id; })
                    .map(function (card) { return card.id; }),
            };
        });
        var normalized = {
            format: FORMAT_NAME,
            version: FORMAT_VERSION,
            title: title,
            source: "source" in pack ? pack.source : { type: "manual" },
            ai: ai,
            decks: normalizedDecks,
            cards: cards,
        };
        if (mediaDir != null) {
            normalized.media_dir = mediaDir;
        }
        return normalized;
    }

    // ------------------------------------------------------------------
    // JSON serialisation matching json.dumps(..., sort_keys=True, indent=2)
    // ------------------------------------------------------------------

    function dumpsSorted(value, level) {
        level = level || 0;
        var indent = new Array(level * 2 + 1).join(" ");
        var inner = new Array((level + 1) * 2 + 1).join(" ");
        if (value === null) {
            return "null";
        }
        var type = typeof value;
        if (type === "boolean") {
            return value ? "true" : "false";
        }
        if (type === "number") {
            return Number.isInteger(value) ? String(value) : String(value);
        }
        if (type === "string") {
            return JSON.stringify(value);
        }
        if (Array.isArray(value)) {
            if (!value.length) {
                return "[]";
            }
            return "[\n" + value.map(function (item) {
                return inner + dumpsSorted(item, level + 1);
            }).join(",\n") + "\n" + indent + "]";
        }
        var keys = Object.keys(value).sort();
        if (!keys.length) {
            return "{}";
        }
        return "{\n" + keys.map(function (key) {
            return inner + JSON.stringify(key) + ": " + dumpsSorted(value[key], level + 1);
        }).join(",\n") + "\n" + indent + "}";
    }

    // ------------------------------------------------------------------
    // Bundle writing (port of kindle_bundle.write_kindle_bundle)
    // ------------------------------------------------------------------

    var WINDOWS_RESERVED = {};
    ["CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
        .forEach(function (name) { WINDOWS_RESERVED[name] = true; });

    function safeStem(title, fallback) {
        var cleaned = String(title == null ? "" : title)
            .replace(/[\\/:*?"<>|\x00-\x1f]+/g, " ");
        cleaned = cleaned.replace(/\s+/g, " ").trim()
            .replace(/^[. ]+/, "").replace(/[. ]+$/, "");
        if (!cleaned) {
            return fallback || "kindle-anki";
        }
        if (cleaned.toUpperCase() in WINDOWS_RESERVED) {
            cleaned = "_" + cleaned;
        }
        cleaned = cleaned.slice(0, 80).replace(/[. ]+$/, "");
        return cleaned || fallback || "kindle-anki";
    }

    function packStem(fileName) {
        var name = String(fileName || "").split("/").pop().split("\\").pop();
        var suffixes = [PACK_SUFFIX, ".folo-kindle.json", ".kindle-anki", ".folo-kindle"];
        for (var i = 0; i < suffixes.length; i++) {
            if (name.slice(-suffixes[i].length) === suffixes[i]) {
                return name.slice(0, name.length - suffixes[i].length);
            }
        }
        var dot = name.lastIndexOf(".");
        return dot > 0 ? name.slice(0, dot) : name;
    }

    function writeKindleBundle(pack, archive, options) {
        options = options || {};
        var stem = safeStem(String(pack.title || "").trim(),
            packStem(options.fileName));
        var mediaName = stem + MEDIA_SUFFIX;
        var working = {};
        Object.keys(pack).forEach(function (key) { working[key] = pack[key]; });
        working.media_dir = mediaName;
        var normalized = validatePackage(working);
        if (normalized.ai && typeof normalized.ai === "object") {
            delete normalized.ai.api_key;
        }
        var jsonName = stem + PACK_SUFFIX;
        var jsonBytes = dumpsSorted(normalized) + "\n";

        var references = {};
        normalized.cards.forEach(function (card) {
            ["front_images", "back_images"].forEach(function (field) {
                (card[field] || []).forEach(function (image) {
                    references[image.name] = true;
                });
            });
        });
        return archive.mediaCatalog().then(function (catalog) {
            var byOutputName = {};
            Object.keys(catalog).forEach(function (sourceName) {
                var asset = catalog[sourceName];
                byOutputName[asset.name] = asset;
            });
            var names = Object.keys(references).sort();
            var reads = [];
            names.forEach(function (name) {
                var asset = byOutputName[name];
                if (asset) {
                    reads.push(archive.zip.read(asset.archiveName).then(function (data) {
                        return { name: name, data: data };
                    }));
                }
            });
            return Promise.all(reads);
        }).then(function (media) {
            var total = 0;
            media.forEach(function (file) { total += file.data.length; });
            if (total > K.MAX_ZIP_ENTRY_BYTES * 4) {
                throw AnkiError("extracted media exceeds the total size limit");
            }
            media.sort(function (a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0; });
            var writer = new K.ZipWriter();
            writer.add(jsonName, jsonBytes);
            media.forEach(function (file) {
                writer.add(mediaName + "/" + file.name, file.data);
            });
            return {
                stem: stem,
                jsonName: jsonName,
                mediaName: mediaName,
                zipName: stem + ZIP_SUFFIX,
                zipBytes: writer.finish(),
                extracted: media.length,
                cards: normalized.cards.length,
            };
        });
    }

    return {
        AnkiError: AnkiError,
        PackageError: PackageError,
        FORMAT_NAME: FORMAT_NAME,
        FORMAT_VERSION: FORMAT_VERSION,
        htmlToText: htmlToText,
        decodeEntities: decodeEntities,
        detectModels: detectModels,
        correctIndices: correctIndices,
        embeddedChoice: embeddedChoice,
        packedOptions: packedOptions,
        safeStem: safeStem,
        packStem: packStem,
        validatePackage: validatePackage,
        dumpsSorted: dumpsSorted,
        openArchive: function (fileBytes, fileName) {
            return new ApkgArchive(fileBytes, fileName);
        },
        importApkg: importApkg,
        inspectApkg: inspectApkg,
        writeKindleBundle: writeKindleBundle,
    };
});
