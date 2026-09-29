#!/usr/bin/env node
/* Test bridge: print JSON array of convert.safeStem(title) results for stdin cases. */
"use strict";

const path = require("path");
const convert = require(path.resolve(
    __dirname, "..", "..", "plugin", "kindleanki.koplugin", "web", "convert.js"));

const cases = JSON.parse(process.argv[2] || "[]");
process.stdout.write(JSON.stringify(cases.map(function (title) {
    return convert.safeStem(title, "kindle-anki");
})));
