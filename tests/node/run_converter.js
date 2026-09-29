#!/usr/bin/env node
/*
 * Test bridge: run the browser converter against an .apkg and dump the
 * results as JSON/files so tests/test_kindle_web_converter.py can compare
 * them byte-for-field against the Python importer.
 *
 * Usage:
 *   node run_converter.js <apkg> <out-pkg.json> [out-zip]
 *   node run_converter.js --inspect <apkg> <out-inspect.json>
 */
"use strict";

const fs = require("fs");
const path = require("path");

const WEB_DIR = path.resolve(__dirname, "..", "..", "plugin", "kindleanki.koplugin", "web");
const convert = require(path.join(WEB_DIR, "convert.js"));

function fail(message) {
    process.stderr.write(message + "\n");
    process.exit(1);
}

async function main() {
    const args = process.argv.slice(2);
    const options = {};
    while (args.length && args[0].startsWith("--")) {
        const flag = args.shift();
        if (flag === "--inspect") {
            options.inspect = true;
        } else if (flag === "--no-ai") {
            options.noAi = true;
        } else if (flag === "--title") {
            options.title = args.shift();
        } else if (flag === "--map") {
            options.mapping = JSON.parse(fs.readFileSync(args.shift(), "utf-8"));
        } else {
            fail("unknown flag " + flag);
        }
    }
    if (args.length < 2) {
        fail("usage: run_converter.js [--inspect] [--no-ai] [--title X] [--map m.json] <apkg> <out.json> [out.zip]");
    }
    const apkgPath = args[0];
    const outPath = args[1];
    const outZipPath = args[2];

    const fileBytes = fs.readFileSync(apkgPath);
    const fileName = path.basename(apkgPath);
    const ai = options.noAi ? {} : {
        endpoint: "https://api.example/v1",
        model: "demo-model",
        api_key: "pack-test-key",
    };

    if (options.inspect) {
        const info = await convert.inspectApkg(fileBytes, fileName);
        fs.writeFileSync(outPath, JSON.stringify(info));
        process.stdout.write("ok\n");
        return;
    }

    const archive = convert.openArchive(fileBytes, fileName);
    const pack = await convert.importApkg(fileBytes, fileName, {
        ai: ai,
        fieldMapping: options.mapping || null,
        title: options.title || null,
    });
    fs.writeFileSync(outPath, JSON.stringify(pack));
    if (outZipPath) {
        const bundle = await convert.writeKindleBundle(pack, archive, { fileName: fileName });
        fs.writeFileSync(outZipPath, Buffer.from(bundle.zipBytes));
    }
    process.stdout.write("ok\n");
}

main().catch(function (error) {
    process.stderr.write((error && error.stack) || String(error) + "\n");
    process.exit(1);
});
