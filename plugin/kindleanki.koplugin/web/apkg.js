/*
 * Low-level .apkg reading helpers for the browser converter: a zip reader,
 * a zip writer, a minimal read-only SQLite parser, and image size sniffing.
 *
 * No external dependencies. Zip decompression uses the standard
 * DecompressionStream; the SQLite side only decodes what the legacy Anki
 * collection contains (plain rowid tables), which mirrors what the desktop
 * Python importer reads through sqlite3.
 *
 * Exposed as window.KindleApkg in the browser, module.exports under Node.
 */
(function (root, factory) {
    "use strict";
    var api = factory();
    if (typeof module !== "undefined" && module.exports) {
        module.exports = api;
    } else {
        root.KindleApkg = api;
    }
})(typeof self !== "undefined" ? self : this, function () {
    "use strict";

    var MAX_ZIP_ENTRY_BYTES = 512 * 1024 * 1024;
    var MAX_EXTRACTED_MEDIA_BYTES = MAX_ZIP_ENTRY_BYTES * 4;

    function unsupported(message) {
        throw new Error(message);
    }

    // ------------------------------------------------------------------
    // Byte helpers
    // ------------------------------------------------------------------

    function u16be(bytes, offset) {
        return (bytes[offset] << 8) | bytes[offset + 1];
    }

    function u32be(bytes, offset) {
        return ((bytes[offset] << 24) | (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) | bytes[offset + 3]) >>> 0;
    }

    function u48be(bytes, offset) {
        var high = u16be(bytes, offset);
        var low = u32be(bytes, offset + 2);
        return high * 0x100000000 + low;
    }

    function u64be(bytes, offset) {
        var high = u32be(bytes, offset);
        var low = u32be(bytes, offset + 4);
        return high * 0x100000000 + low;
    }

    // Zip structures are little-endian; SQLite headers are big-endian.
    function u16le(bytes, offset) {
        return bytes[offset] | (bytes[offset + 1] << 8);
    }

    function u32le(bytes, offset) {
        return (bytes[offset] | (bytes[offset + 1] << 8) |
            (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
    }

    function u64le(bytes, offset) {
        return u32le(bytes, offset) + u32le(bytes, offset + 4) * 0x100000000;
    }

    var utf8Decoder = new TextDecoder("utf-8");

    // ------------------------------------------------------------------
    // CRC32 (zip writing)
    // ------------------------------------------------------------------

    var CRC_TABLE = (function () {
        var table = new Uint32Array(256);
        for (var n = 0; n < 256; n++) {
            var c = n;
            for (var k = 0; k < 8; k++) {
                c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
            }
            table[n] = c >>> 0;
        }
        return table;
    })();

    function crc32(bytes) {
        var crc = 0xFFFFFFFF;
        for (var i = 0; i < bytes.length; i++) {
            crc = CRC_TABLE[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
        }
        return (crc ^ 0xFFFFFFFF) >>> 0;
    }

    // ------------------------------------------------------------------
    // Zip reader
    // ------------------------------------------------------------------

    function inflateRaw(data) {
        if (typeof DecompressionStream === "undefined") {
            return Promise.reject(new Error(
                "this browser cannot unzip .apkg files; please update it or use the desktop converter"));
        }
        var stream = new Blob([data]).stream()
            .pipeThrough(new DecompressionStream("deflate-raw"));
        return new Response(stream).arrayBuffer().then(function (buffer) {
            return new Uint8Array(buffer);
        });
    }

    function findEocd(bytes) {
        var lowest = Math.max(0, bytes.length - (22 + 65535));
        for (var i = bytes.length - 22; i >= lowest; i--) {
            if (bytes[i] === 0x50 && bytes[i + 1] === 0x4B &&
                bytes[i + 2] === 0x05 && bytes[i + 3] === 0x06) {
                return i;
            }
        }
        return -1;
    }

    function parseCentralDirectory(bytes) {
        var eocd = findEocd(bytes);
        if (eocd < 0) {
            unsupported("not a zip archive");
        }
        var totalEntries = u16le(bytes, eocd + 10);
        var cdSize = u32le(bytes, eocd + 12);
        var cdOffset = u32le(bytes, eocd + 16);
        if (totalEntries === 0xFFFF || cdSize === 0xFFFFFFFF || cdOffset === 0xFFFFFFFF) {
            // Zip64: the locator sits directly before the EOCD record.
            var locator = eocd - 20;
            if (locator < 0 || bytes[locator] !== 0x50 || bytes[locator + 1] !== 0x4B ||
                bytes[locator + 2] !== 0x06 || bytes[locator + 3] !== 0x07) {
                unsupported("zip64 archive locator not found");
            }
            var zip64Offset = u64le(bytes, locator + 8);
            if (u32le(bytes, zip64Offset) !== 0x06064B50) {
                unsupported("zip64 end of central directory not found");
            }
            totalEntries = u64le(bytes, zip64Offset + 32);
            cdSize = u64le(bytes, zip64Offset + 40);
            cdOffset = u64le(bytes, zip64Offset + 48);
        }
        var entries = [];
        var offset = cdOffset;
        for (var index = 0; index < totalEntries; index++) {
            if (offset + 46 > bytes.length || u32le(bytes, offset) !== 0x02014B50) {
                unsupported("corrupted zip central directory");
            }
            var flags = u16le(bytes, offset + 8);
            var method = u16le(bytes, offset + 10);
            var compSize = u32le(bytes, offset + 20);
            var uncompSize = u32le(bytes, offset + 24);
            var nameLen = u16le(bytes, offset + 28);
            var extraLen = u16le(bytes, offset + 30);
            var commentLen = u16le(bytes, offset + 32);
            var localOffset = u32le(bytes, offset + 42);
            var extraStart = offset + 46 + nameLen;
            if (compSize === 0xFFFFFFFF || uncompSize === 0xFFFFFFFF || localOffset === 0xFFFFFFFF) {
                var cursor = extraStart;
                var extraEnd = extraStart + extraLen;
                while (cursor + 4 <= extraEnd) {
                    var headerId = u16le(bytes, cursor);
                    var fieldSize = u16le(bytes, cursor + 2);
                    if (headerId === 0x0001) {
                        var field = cursor + 4;
                        if (uncompSize === 0xFFFFFFFF && field + 8 <= extraEnd) {
                            uncompSize = u64le(bytes, field);
                            field += 8;
                        }
                        if (compSize === 0xFFFFFFFF && field + 8 <= extraEnd) {
                            compSize = u64le(bytes, field);
                            field += 8;
                        }
                        if (localOffset === 0xFFFFFFFF && field + 8 <= extraEnd) {
                            localOffset = u64le(bytes, field);
                            field += 8;
                        }
                        break;
                    }
                    cursor += 4 + fieldSize;
                }
            }
            var nameBytes = bytes.subarray(offset + 46, offset + 46 + nameLen);
            var name = utf8Decoder.decode(nameBytes);
            entries.push({
                name: name,
                flags: flags,
                method: method,
                compSize: compSize,
                uncompSize: uncompSize,
                localOffset: localOffset,
            });
            offset = extraStart + extraLen + commentLen;
        }
        return entries;
    }

    function ZipReader(bytes) {
        this.bytes = bytes;
        this.entries = parseCentralDirectory(bytes);
        this.byName = Object.create(null);
        for (var i = 0; i < this.entries.length; i++) {
            var entry = this.entries[i];
            if (!(entry.name in this.byName)) {
                this.byName[entry.name] = entry;
            }
        }
    }

    ZipReader.prototype.has = function (name) {
        return name in this.byName;
    };

    ZipReader.prototype.read = function (name) {
        var entry = this.byName[name];
        if (!entry) {
            return Promise.reject(new Error("zip entry " + name + " not found"));
        }
        return this.readEntry(entry);
    };

    ZipReader.prototype.readEntry = function (entry) {
        if (entry.uncompSize > MAX_ZIP_ENTRY_BYTES) {
            return Promise.reject(new Error(
                "zip entry " + entry.name + " is too large to read"));
        }
        if (entry.flags & 0x0001) {
            return Promise.reject(new Error(
                "zip entry " + entry.name + " is encrypted"));
        }
        var bytes = this.bytes;
        var local = entry.localOffset;
        if (local + 30 > bytes.length || u32le(bytes, local) !== 0x04034B50) {
            return Promise.reject(new Error(
                "corrupted zip local header for " + entry.name));
        }
        var nameLen = u16le(bytes, local + 26);
        var extraLen = u16le(bytes, local + 28);
        var start = local + 30 + nameLen + extraLen;
        var data = bytes.subarray(start, start + entry.compSize);
        if (entry.method === 0) {
            return Promise.resolve(data);
        }
        if (entry.method !== 8) {
            return Promise.reject(new Error(
                "zip entry " + entry.name + " uses unsupported compression " + entry.method));
        }
        return inflateRaw(data);
    };

    // ------------------------------------------------------------------
    // Zip writer (stored entries; deflate adds nothing for images and is
    // unnecessary for the JSON the Kindle unpacks seconds later)
    // ------------------------------------------------------------------

    function dosDateTime(date) {
        date = date || new Date();
        var year = Math.max(1980, date.getFullYear());
        var dosTime = (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1);
        var dosDate = ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
        return { time: dosTime & 0xFFFF, date: dosDate & 0xFFFF };
    }

    function ZipWriter() {
        this.files = [];
    }

    ZipWriter.prototype.add = function (name, data) {
        if (this.files.length >= 0xFFFF) {
            unsupported("too many files for a zip archive");
        }
        data = data instanceof Uint8Array ? data : new TextEncoder().encode(String(data));
        if (data.length > MAX_ZIP_ENTRY_BYTES) {
            unsupported("file " + name + " is too large to store");
        }
        this.files.push({ name: name, data: data, crc: crc32(data), stamp: dosDateTime() });
    };

    ZipWriter.prototype.finish = function () {
        var parts = [];
        var centralParts = [];
        var offset = 0;
        var encoder = new TextEncoder();
        for (var i = 0; i < this.files.length; i++) {
            var file = this.files[i];
            var nameBytes = encoder.encode(file.name);
            var needsUtf8 = /[^\x00-\x7F]/.test(file.name);
            var flags = needsUtf8 ? 0x0800 : 0;
            var local = new Uint8Array(30 + nameBytes.length);
            var view = new DataView(local.buffer);
            view.setUint32(0, 0x04034B50, true);
            view.setUint16(4, 20, true);
            view.setUint16(6, flags, true);
            view.setUint16(8, 0, true); // stored
            view.setUint16(10, file.stamp.time, true);
            view.setUint16(12, file.stamp.date, true);
            view.setUint32(14, file.crc, true);
            view.setUint32(18, file.data.length, true);
            view.setUint32(22, file.data.length, true);
            view.setUint16(26, nameBytes.length, true);
            view.setUint16(28, 0, true);
            local.set(nameBytes, 30);
            parts.push(local, file.data);

            var central = new Uint8Array(46 + nameBytes.length);
            var cview = new DataView(central.buffer);
            cview.setUint32(0, 0x02014B50, true);
            cview.setUint16(4, 20, true);
            cview.setUint16(6, 20, true);
            cview.setUint16(8, flags, true);
            cview.setUint16(10, 0, true);
            cview.setUint16(12, file.stamp.time, true);
            cview.setUint16(14, file.stamp.date, true);
            cview.setUint32(16, file.crc, true);
            cview.setUint32(20, file.data.length, true);
            cview.setUint32(24, file.data.length, true);
            cview.setUint16(28, nameBytes.length, true);
            cview.setUint32(42, offset, true);
            central.set(nameBytes, 46);
            centralParts.push(central);

            offset += local.length + file.data.length;
        }
        var centralStart = offset;
        for (var j = 0; j < centralParts.length; j++) {
            offset += centralParts[j].length;
        }
        var end = new Uint8Array(22);
        var eview = new DataView(end.buffer);
        eview.setUint32(0, 0x06054B50, true);
        eview.setUint16(8, this.files.length, true);
        eview.setUint16(10, this.files.length, true);
        eview.setUint32(12, offset - centralStart, true);
        eview.setUint32(16, centralStart, true);
        parts.push.apply(parts, centralParts);
        parts.push(end);
        var total = 0;
        for (var k = 0; k < parts.length; k++) total += parts[k].length;
        var out = new Uint8Array(total);
        var position = 0;
        for (var m = 0; m < parts.length; m++) {
            out.set(parts[m], position);
            position += parts[m].length;
        }
        return out;
    };

    // ------------------------------------------------------------------
    // Minimal read-only SQLite parser (table b-trees only)
    // ------------------------------------------------------------------

    function readVarint(bytes, offset) {
        var value = 0n;
        for (var i = 0; i < 8; i++) {
            var byte = bytes[offset + i];
            value = (value << 7n) | BigInt(byte & 0x7F);
            if (!(byte & 0x80)) {
                return { value: value, next: offset + i + 1 };
            }
        }
        value = (value << 8n) | BigInt(bytes[offset + 8]);
        return { value: value, next: offset + 9 };
    }

    function signedInt(bytes, offset, length) {
        var value = 0n;
        for (var i = 0; i < length; i++) {
            value = (value << 8n) | BigInt(bytes[offset + i]);
        }
        if (length < 8) {
            var bits = BigInt(length * 8);
            if (value >= (1n << (bits - 1n))) {
                value -= (1n << bits);
            }
        } else {
            value = BigInt.asIntN(64, value);
        }
        return Number(value);
    }

    var SERIAL_FIXED = { 1: 1, 2: 2, 3: 3, 4: 4, 5: 6, 6: 8, 7: 8, 8: 0, 9: 0 };

    function decodeRecord(payload) {
        var headerSize = Number(readVarint(payload, 0).value);
        var types = [];
        var cursor = readVarint(payload, 0).next;
        while (cursor < headerSize) {
            var type = readVarint(payload, cursor);
            types.push(Number(type.value));
            cursor = type.next;
        }
        var body = headerSize;
        var row = [];
        var floatView = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
        for (var i = 0; i < types.length; i++) {
            var serial = types[i];
            if (serial === 0) {
                row.push(null);
            } else if (serial >= 1 && serial <= 6) {
                row.push(signedInt(payload, body, SERIAL_FIXED[serial]));
                body += SERIAL_FIXED[serial];
            } else if (serial === 7) {
                row.push(floatView.getFloat64(body, false));
                body += 8;
            } else if (serial === 8) {
                row.push(0);
            } else if (serial === 9) {
                row.push(1);
            } else if (serial >= 12 && serial % 2 === 0) {
                var blobLength = (serial - 12) / 2;
                row.push(payload.subarray(body, body + blobLength));
                body += blobLength;
            } else if (serial >= 13) {
                var textLength = (serial - 13) / 2;
                row.push(utf8Decoder.decode(payload.subarray(body, body + textLength)));
                body += textLength;
            } else {
                unsupported("corrupted sqlite record");
            }
        }
        return row;
    }

    function walkTableBtree(bytes, pageSize, reserved, pageNumber, visit) {
        // Iterative walk with an explicit stack so hundred-thousand-row
        // collections cannot overflow the call stack.
        var usable = pageSize - reserved;
        var stack = [pageNumber];
        var guard = 0;
        while (stack.length) {
            if (++guard > 10000000) {
                unsupported("sqlite table walk exceeded a sane page budget");
            }
            var page = stack.pop();
            var base = (page - 1) * pageSize;
            var header = base + (page === 1 ? 100 : 0);
            var type = bytes[header];
            var cellCount = u16be(bytes, header + 3);
            if (type === 0x05) { // interior table page
                var pointers = header + 12;
                var children = [];
                for (var c = 0; c < cellCount; c++) {
                    var pointer = base + u16be(bytes, pointers + c * 2);
                    children.push(u32be(bytes, pointer));
                }
                children.push(u32be(bytes, header + 8));
                for (var d = children.length - 1; d >= 0; d--) {
                    stack.push(children[d]);
                }
            } else if (type === 0x0D) { // leaf table page
                var leafPointers = header + 8;
                for (var l = 0; l < cellCount; l++) {
                    var cell = base + u16be(bytes, leafPointers + l * 2);
                    var payloadLength = Number(readVarint(bytes, cell).value);
                    var afterLength = readVarint(bytes, cell).next;
                    var rowid = readVarint(bytes, afterLength);
                    var payloadStart = rowid.next;
                    var maxLocal = usable - 35;
                    var localLength = payloadLength;
                    if (payloadLength > maxLocal) {
                        var minLocal = Math.floor((usable - 12) * 32 / 255) - 23;
                        var candidate = minLocal + ((payloadLength - minLocal) % (usable - 4));
                        localLength = candidate <= maxLocal ? candidate : minLocal;
                    }
                    var payload;
                    if (localLength === payloadLength) {
                        payload = bytes.subarray(payloadStart, payloadStart + payloadLength);
                    } else {
                        var overflowPage = u32be(bytes, payloadStart + localLength);
                        payload = new Uint8Array(payloadLength);
                        payload.set(bytes.subarray(payloadStart, payloadStart + localLength), 0);
                        var filled = localLength;
                        var hopGuard = 0;
                        while (filled < payloadLength) {
                            if (++hopGuard > 10000000 || overflowPage === 0) {
                                unsupported("corrupted sqlite overflow chain");
                            }
                            var overflowBase = (overflowPage - 1) * pageSize;
                            overflowPage = u32be(bytes, overflowBase);
                            var chunk = Math.min(usable - 4, payloadLength - filled);
                            payload.set(bytes.subarray(overflowBase + 4, overflowBase + 4 + chunk), filled);
                            filled += chunk;
                        }
                    }
                    visit(Number(rowid.value), payload);
                }
            } else {
                unsupported("unexpected sqlite page type " + type);
            }
        }
    }

    function parseColumns(sql) {
        var open = sql.indexOf("(");
        var close = sql.lastIndexOf(")");
        if (open < 0 || close <= open) {
            return [];
        }
        // Real Anki exports annotate every column with ordinal comments
        // (e.g. "/* 0 */ guid text not null"); strip comments and quoted
        // literals before splitting, or the name match fails.
        var body = sql.slice(open + 1, close)
            .replace(/\/\*[\s\S]*?\*\//g, " ")
            .replace(/--[^\r\n]*/g, " ")
            .replace(/'(?:[^']|'')*'/g, "''");
        var columns = [];
        var depth = 0;
        var current = "";
        for (var i = 0; i < body.length; i++) {
            var ch = body[i];
            if (ch === "(") depth++;
            if (ch === ")") depth--;
            if (ch === "," && depth === 0) {
                columns.push(current);
                current = "";
            } else {
                current += ch;
            }
        }
        columns.push(current);
        var names = [];
        var skip = /^(primary|unique|check|foreign|constraint)\b/i;
        var quoted = /^\s*(?:"([^"]+)"|`([^`]+)`|\[([^\]]+)\]|([A-Za-z_][A-Za-z0-9_$]*))/;
        for (var c = 0; c < columns.length; c++) {
            var definition = columns[c].trim();
            if (!definition || skip.test(definition)) {
                continue;
            }
            var match = quoted.exec(definition);
            if (!match) {
                unsupported("cannot parse sqlite column " + definition);
            }
            names.push({
                name: match[1] || match[2] || match[3] || match[4],
                // A rowid-alias column stores NULL in the record; the real
                // value lives in the b-tree cell's rowid.
                isRowidAlias: /integer\s+primary\s+key/i.test(definition),
            });
        }
        return names;
    }

    function SQLite(bytes) {
        if (bytes.length < 100 || utf8Decoder.decode(bytes.subarray(0, 16)) !== "SQLite format 3\u0000") {
            unsupported("not a sqlite database");
        }
        var pageSize = u16be(bytes, 16);
        if (pageSize === 1) {
            pageSize = 65536;
        }
        if (pageSize < 512 || (pageSize & (pageSize - 1)) !== 0) {
            unsupported("invalid sqlite page size");
        }
        var reserved = bytes[20];
        if (u32be(bytes, 56) !== 1) {
            unsupported("only UTF-8 sqlite databases are supported");
        }
        this.bytes = bytes;
        this.pageSize = pageSize;
        this.reserved = reserved;
        this._master = null;
    }

    SQLite.prototype.master = function () {
        if (this._master) {
            return this._master;
        }
        var self = this;
        var tables = {};
        walkTableBtree(this.bytes, this.pageSize, this.reserved, 1, function (rowid, payload) {
            var row = decodeRecord(payload);
            if (row.length >= 5 && row[0] === "table" && typeof row[4] === "string") {
                tables[row[1]] = { rootPage: Number(row[3]), sql: row[4] };
            }
        });
        this._master = tables;
        return tables;
    };

    SQLite.prototype.table = function (name) {
        var definition = this.master()[name];
        if (!definition) {
            return null;
        }
        var columns = parseColumns(definition.sql);
        var rows = [];
        walkTableBtree(this.bytes, this.pageSize, this.reserved, definition.rootPage, function (rowid, payload) {
            var values = decodeRecord(payload);
            var row = { rowid: rowid };
            for (var i = 0; i < columns.length; i++) {
                var column = columns[i];
                var value = i < values.length ? values[i] : null;
                row[column.name] = value === null && column.isRowidAlias ? rowid : value;
            }
            rows.push(row);
        });
        // Without-rowid tables aside, cells arrive in rowid order already;
        // the sort keeps the guarantee explicit for the col/notes/cards reads.
        rows.sort(function (a, b) { return a.rowid - b.rowid; });
        return { columns: columns.map(function (column) { return column.name; }), rows: rows };
    };

    // ------------------------------------------------------------------
    // Image size sniffing (PNG / GIF / JPEG headers)
    // ------------------------------------------------------------------

    function imageDimensions(data) {
        if (data.length >= 24 && data[0] === 0x89 && data[1] === 0x50 && data[2] === 0x4E && data[3] === 0x47) {
            return { width: u32be(data, 16), height: u32be(data, 20) };
        }
        if (data.length >= 10 && data[0] === 0x47 && data[1] === 0x49 && data[2] === 0x46) {
            return { width: data[6] | (data[7] << 8), height: data[8] | (data[9] << 8) };
        }
        if (data.length < 4 || data[0] !== 0xFF || data[1] !== 0xD8) {
            return null;
        }
        var sofMarkers = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF];
        var offset = 2;
        while (offset + 9 < data.length) {
            while (offset < data.length && data[offset] !== 0xFF) offset++;
            while (offset < data.length && data[offset] === 0xFF) offset++;
            if (offset >= data.length) break;
            var marker = data[offset];
            offset += 1;
            if (marker === 0xD8 || marker === 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
                continue;
            }
            if (offset + 2 > data.length) break;
            var length = u16be(data, offset);
            if (length < 2 || offset + length > data.length) break;
            if (sofMarkers.indexOf(marker) >= 0 && length >= 7) {
                return {
                    height: u16be(data, offset + 3),
                    width: u16be(data, offset + 5),
                };
            }
            offset += length;
        }
        return null;
    }

    return {
        MAX_ZIP_ENTRY_BYTES: MAX_ZIP_ENTRY_BYTES,
        ZipReader: ZipReader,
        ZipWriter: ZipWriter,
        SQLite: SQLite,
        crc32: crc32,
        imageDimensions: imageDimensions,
    };
});
