// Run: node --test widgets/scriptable/test
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { load } = require("./load");

const sample = fs.readFileSync(path.join(__dirname, "sample-snapshot.json"), "utf8");
const at = (iso) => new Date(iso);

test("updated label and staleness", async () => {
  const w = await load();
  const updated = "2026-10-19T12:05:00Z";
  assert.equal(w.updatedLabel(updated, at("2026-10-19T12:05:20Z")), "Updated just now");
  assert.equal(w.updatedLabel(updated, at("2026-10-19T12:10:00Z")), "Updated 5m ago");
  assert.equal(w.updatedLabel(updated, at("2026-10-19T14:06:00Z")), "Updated 2h ago");
  assert.equal(w.updatedLabel(updated, at("2026-10-22T12:05:00Z")), "Updated 3d ago");
  assert.equal(w.isStale(updated, at("2026-10-19T12:35:00Z")), false);
  assert.equal(w.isStale(updated, at("2026-10-19T12:36:00Z")), true);
  assert.equal(w.isStale("garbage", at("2026-10-19T12:06:00Z")), true);
});

test("colors follow percent left", async () => {
  const w = await load();
  assert.equal(w.colorForPercent(100), w.COLORS.green);
  assert.equal(w.colorForPercent(50), w.COLORS.green);
  assert.equal(w.colorForPercent(49), w.COLORS.amber);
  assert.equal(w.colorForPercent(20), w.COLORS.amber);
  assert.equal(w.colorForPercent(19), w.COLORS.red);
  assert.equal(w.colorForPercent(-5), w.COLORS.red);
});

test("reset labels", async () => {
  const w = await load();
  const now = at("2026-10-19T12:00:00Z");
  assert.equal(w.resetLabel("2026-10-19T14:10:00Z", now), "Resets in 2h 10m");
  assert.equal(w.resetLabel("2026-10-21T16:00:00Z", now), "Resets in 2d 4h");
  assert.equal(w.resetLabel("2026-10-19T12:00:30Z", now), "Resets now");
  assert.equal(w.resetLabel("2026-10-19T11:00:00Z", now), "Resets now");
  assert.equal(w.resetLabel(undefined, now), "");
});

test("rows pick the tightest limit and honor the filter", async () => {
  const w = await load();
  const model = w.buildModel(sample, "medium", at("2026-10-19T12:10:00Z"));
  assert.equal(model.kind, "usage");
  assert.deepEqual(model.rows.map((r) => [r.name, r.percentLeft, r.label]), [
    ["Claude", 58, "5-hour window"],
    ["GPT", 34, "This week"],
    ["Cursor", 12, "Weekly limit"],
    ["Grok", 72, "This week"],
  ]);
  assert.equal(model.updated, "Updated 5m ago");
  assert.equal(model.stale, false);
  assert.equal(w.buildModel(sample, "small", at("2026-10-19T12:10:00Z")).rows.length, 3);
  const filtered = w.buildModel(sample, "medium", at("2026-10-19T12:10:00Z"), "claude, Cursor");
  assert.deepEqual(filtered.rows.map((r) => r.name), ["Claude", "Cursor"]);
  assert.equal(w.inlineText(filtered), "Claude 58% · Cursor 12%");
  const old = w.buildModel(sample, "accessoryInline", at("2026-10-19T13:00:00Z"));
  assert.ok(w.inlineText(old).startsWith("Stale · "));
});

test("friendly messages for missing, broken and newer files", async () => {
  const w = await load();
  const now = at("2026-10-19T12:10:00Z");
  const missing = w.buildModel(null, "medium", now);
  assert.equal(missing.kind, "message");
  assert.match(missing.body, /Write a snapshot for the iPhone widget/);
  assert.equal(w.buildModel("{oops", "medium", now).title, "Can't read usage");
  assert.equal(w.buildModel('{"version":2,"providers":[]}', "medium", now).title, "Update the widget");
  assert.equal(w.buildModel('{"version":1,"updatedAt":"x","providers":[]}', "medium", now).title, "No usage yet");
});

// Minimal fakes so every layout runs end to end without an iPhone.
function fakeScriptable(family, fileText) {
  const log = [];
  class Stack {
    constructor() { this.items = []; }
    addStack() { const s = new Stack(); this.items.push(s); return s; }
    addText(t) { log.push(String(t)); const o = { text: t }; this.items.push(o); return Object.assign(o, { centerAlignText() {} }); }
    addImage(img) { const o = { img }; this.items.push(o); return o; }
    addSpacer() {}
    centerAlignContent() {}
    setPadding() {}
  }
  class ListWidget extends Stack {
    async presentMedium() {}
  }
  class DrawContext { addPath() {} setFillColor() {} fillPath() {} getImage() { return {}; } }
  const files = { "/icloud/tum-snapshot.json": fileText };
  const FileManager = {
    iCloud: () => ({
      documentsDirectory: () => "/icloud",
      joinPath: (a, b) => `${a}/${b}`,
      fileExists: (p) => files[p] != null,
      downloadFileFromiCloud: async () => {},
      readString: (p) => files[p],
      bookmarkExists: () => false,
    }),
  };
  let set = null;
  const Script = { name: () => "Token Usage Monitor", setWidget: (w) => { set = w; }, complete() {} };
  return {
    globals: {
      ListWidget, DrawContext, FileManager, Script,
      Size: class {}, Rect: class {}, Path: class { addRoundedRect() {} },
      Color: class { constructor(h) { this.hex = h; } },
      Font: new Proxy({}, { get: () => () => ({}) }),
      config: { widgetFamily: family, runsInWidget: true },
      args: { widgetParameter: null },
    },
    log,
    widget: () => set,
  };
}

for (const family of ["small", "medium", "accessoryRectangular", "accessoryInline", "accessoryCircular"]) {
  test(`renders ${family} with data and without`, async () => {
    const withData = fakeScriptable(family, sample);
    await load(withData.globals);
    assert.ok(withData.widget(), "widget set");
    assert.ok(withData.log.join(" ").match(/Claude|TUM/));
    const empty = fakeScriptable(family, null);
    await load(empty.globals);
    assert.ok(empty.widget(), "widget set when file missing");
  });
}
