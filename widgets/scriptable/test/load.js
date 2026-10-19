// Loads the Scriptable script in Node. Pass fake Scriptable globals to exercise the layouts.
const fs = require("fs");
const path = require("path");

const source = fs.readFileSync(path.join(__dirname, "..", "token-usage-monitor.js"), "utf8");

async function load(globals = {}) {
  const module = { exports: {} };
  const names = Object.keys(globals);
  const run = new Function("module", ...names, `return (async () => {\n${source}\n})();`);
  await run(module, ...names.map((n) => globals[n]));
  return module.exports;
}

module.exports = { load };
