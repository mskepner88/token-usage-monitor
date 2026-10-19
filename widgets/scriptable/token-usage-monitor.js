// Token Usage Monitor: free iPhone widget for Scriptable.
// https://github.com/mskepner88/token-usage-monitor
//
// Reads tum-snapshot.json, which the Token Usage Monitor Mac app writes to
// iCloud Drive when "Write a snapshot for the iPhone widget" is on in Settings.
// Runs only on your iPhone. No network calls, no tracking.
//
// Widget parameter (optional): provider names to show, comma-separated,
// for example "Claude" or "Claude, Cursor". Leave empty to show all.

const FILE_NAME = "tum-snapshot.json";
// Scriptable › Settings › File Bookmarks name, only needed if the Mac fell back
// to iCloud Drive › TokenUsageMonitor (see README).
const BOOKMARK_NAME = "TokenUsageMonitor";
const STALE_MINUTES = 30;
const SUPPORTED_VERSION = 1;

const COLORS = {
  background: "#1C1C1E",
  text: "#FFFFFF",
  secondary: "#9A9AA0",
  track: "#3A3A3C",
  green: "#30D158",
  amber: "#FFB340",
  red: "#FF453A",
  stale: "#8E8E93",
};

// ---------- Pure helpers (no Scriptable APIs; tested in Node) ----------

function parseSnapshot(text) {
  if (text == null || String(text).trim() === "") {
    return { ok: false, error: "empty" };
  }
  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return { ok: false, error: "invalid" };
  }
  if (!data || typeof data !== "object" || !Array.isArray(data.providers)) {
    return { ok: false, error: "invalid" };
  }
  if (typeof data.version !== "number" || data.version > SUPPORTED_VERSION) {
    return { ok: false, error: "version" };
  }
  return { ok: true, data };
}

function clampPercent(value) {
  const n = Math.round(Number(value));
  if (!isFinite(n)) return 0;
  return Math.min(100, Math.max(0, n));
}

function colorForPercent(percentLeft) {
  const p = clampPercent(percentLeft);
  if (p >= 50) return COLORS.green;
  if (p >= 20) return COLORS.amber;
  return COLORS.red;
}

function minutesSince(iso, now) {
  const t = Date.parse(iso);
  if (isNaN(t)) return null;
  return Math.max(0, Math.floor((now.getTime() - t) / 60000));
}

function updatedLabel(iso, now) {
  const m = minutesSince(iso, now);
  if (m == null) return "Updated: unknown";
  if (m < 1) return "Updated just now";
  if (m < 60) return `Updated ${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `Updated ${h}h ago`;
  return `Updated ${Math.floor(h / 24)}d ago`;
}

function isStale(iso, now, staleMinutes = STALE_MINUTES) {
  const m = minutesSince(iso, now);
  return m == null || m > staleMinutes;
}

function shortDuration(totalMinutes) {
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  if (days > 0) return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
  if (hours > 0) return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
  return `${Math.max(minutes, 1)}m`;
}

function resetLabel(iso, now) {
  if (!iso) return "";
  const t = Date.parse(iso);
  if (isNaN(t)) return "";
  const seconds = (t - now.getTime()) / 1000;
  if (seconds <= 60) return "Resets now";
  return `Resets in ${shortDuration(Math.floor(seconds / 60))}`;
}

// The limit with the least left is the one that matters.
function tightestLimit(provider) {
  const limits = Array.isArray(provider.limits) ? provider.limits : [];
  if (limits.length === 0) return null;
  return limits.reduce((a, b) => (clampPercent(b.percentLeft) < clampPercent(a.percentLeft) ? b : a));
}

function parseFilter(parameter) {
  if (!parameter) return [];
  return String(parameter)
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
}

function buildRows(snapshot, now, options = {}) {
  const filter = parseFilter(options.filter);
  const max = options.max || 99;
  return snapshot.providers
    .filter((p) => filter.length === 0 || filter.includes(String(p.name).toLowerCase()))
    .map((p) => {
      const limit = tightestLimit(p);
      if (!limit) return null;
      const percentLeft = clampPercent(limit.percentLeft);
      return {
        name: String(p.name),
        plan: p.plan ? String(p.plan) : "",
        label: limit.label ? String(limit.label) : "",
        percentLeft,
        color: colorForPercent(percentLeft),
        reset: resetLabel(limit.resetsAt, now),
      };
    })
    .filter(Boolean)
    .slice(0, max);
}

const FAMILY_MAX_ROWS = {
  small: 3,
  medium: 4,
  large: 8,
  accessoryRectangular: 3,
  accessoryInline: 2,
  accessoryCircular: 1,
};

// Everything a layout needs, as plain data.
function buildModel(fileText, family, now, filter) {
  const parsed = parseSnapshot(fileText);
  if (!parsed.ok) {
    return { kind: "message", family, ...messageFor(parsed.error) };
  }
  const snapshot = parsed.data;
  const rows = buildRows(snapshot, now, { filter, max: FAMILY_MAX_ROWS[family] || 4 });
  if (rows.length === 0) {
    return {
      kind: "message",
      family,
      title: "No usage yet",
      body: filter ? `Nothing matches "${filter}".` : "Open Token Usage Monitor on your Mac and refresh.",
    };
  }
  return {
    kind: "usage",
    family,
    rows,
    updated: updatedLabel(snapshot.updatedAt, now),
    stale: isStale(snapshot.updatedAt, now),
  };
}

function messageFor(error) {
  if (error === "version") {
    return { title: "Update the widget", body: "Copy the latest script from the Token Usage Monitor README." };
  }
  if (error === "invalid") {
    return { title: "Can't read usage", body: "The snapshot file looks damaged. Refresh Token Usage Monitor on your Mac." };
  }
  return {
    title: "Token Usage Monitor",
    body: "No data yet. On your Mac, open Settings and turn on “Write a snapshot for the iPhone widget”.",
  };
}

function inlineText(model) {
  if (model.kind !== "usage") return "TUM: no data yet";
  const parts = model.rows.map((r) => `${r.name} ${r.percentLeft}%`);
  return (model.stale ? "Stale · " : "") + parts.join(" · ");
}

// ---------- Scriptable side ----------

async function readSnapshotText() {
  const fm = FileManager.iCloud();
  const candidates = [fm.joinPath(fm.documentsDirectory(), FILE_NAME)];
  if (fm.bookmarkExists(BOOKMARK_NAME)) {
    candidates.push(fm.joinPath(fm.bookmarkedPath(BOOKMARK_NAME), FILE_NAME));
  }
  for (const path of candidates) {
    if (!fm.fileExists(path)) continue;
    try {
      await fm.downloadFileFromiCloud(path);
      return fm.readString(path);
    } catch (e) {
      // try the next place
    }
  }
  return null;
}

function barImage(percentLeft, color, width, height) {
  const ctx = new DrawContext();
  ctx.size = new Size(width, height);
  ctx.opaque = false;
  ctx.respectScreenScale = true;
  const r = height / 2;
  const track = new Path();
  track.addRoundedRect(new Rect(0, 0, width, height), r, r);
  ctx.addPath(track);
  ctx.setFillColor(new Color(COLORS.track));
  ctx.fillPath();
  const filled = Math.round((width * percentLeft) / 100);
  if (filled > 0) {
    const fill = new Path();
    fill.addRoundedRect(new Rect(0, 0, Math.max(filled, height), height), r, r);
    ctx.addPath(fill);
    ctx.setFillColor(new Color(color));
    ctx.fillPath();
  }
  return ctx.getImage();
}

function addText(stack, text, font, color, lines = 1) {
  const t = stack.addText(text);
  t.font = font;
  t.textColor = new Color(color);
  t.lineLimit = lines;
  t.minimumScaleFactor = 0.7;
  return t;
}

function addFooter(widget, model, small) {
  const footer = widget.addStack();
  footer.centerAlignContent();
  addText(footer, model.updated, Font.systemFont(small ? 9 : 10), COLORS.secondary);
  footer.addSpacer();
  if (model.stale) {
    addText(footer, "Stale", Font.semiboldSystemFont(small ? 9 : 10), COLORS.stale);
  }
}

function renderHomeScreen(model) {
  const small = model.family === "small";
  const widget = new ListWidget();
  widget.backgroundColor = new Color(COLORS.background);
  widget.setPadding(12, 14, 12, 14);
  widget.url = "scriptable:///run/" + encodeURIComponent(Script.name());

  if (model.kind === "message") {
    addText(widget, model.title, Font.boldSystemFont(small ? 13 : 15), COLORS.text, 2);
    widget.addSpacer(4);
    addText(widget, model.body, Font.systemFont(small ? 11 : 12), COLORS.secondary, 5);
    return widget;
  }

  const barWidth = small ? 130 : 310;
  model.rows.forEach((row, i) => {
    if (i > 0) widget.addSpacer(small ? 5 : 6);
    const top = widget.addStack();
    top.centerAlignContent();
    addText(top, row.name, Font.semiboldSystemFont(small ? 12 : 13), COLORS.text);
    if (!small && row.label) {
      top.addSpacer(6);
      addText(top, row.label, Font.systemFont(11), COLORS.secondary);
    }
    top.addSpacer();
    // Medium has room for the reset time on the same line; small puts it under the bar.
    if (!small && row.reset) {
      addText(top, row.reset, Font.systemFont(10), COLORS.secondary);
      top.addSpacer(8);
    }
    addText(top, `${row.percentLeft}%`, Font.boldMonospacedSystemFont(small ? 12 : 13), row.color);
    widget.addSpacer(3);
    const bar = widget.addImage(barImage(row.percentLeft, model.stale ? COLORS.stale : row.color, barWidth, 5));
    bar.imageSize = new Size(barWidth, 5);
    if (small && row.reset) {
      widget.addSpacer(2);
      addText(widget, row.reset, Font.systemFont(9), COLORS.secondary);
    }
  });
  widget.addSpacer();
  addFooter(widget, model, small);
  return widget;
}

function renderLockScreen(model) {
  const widget = new ListWidget();
  widget.url = "scriptable:///run/" + encodeURIComponent(Script.name());
  if (model.family === "accessoryInline") {
    widget.addText(inlineText(model));
    return widget;
  }
  if (model.kind === "message") {
    addText(widget, "TUM", Font.boldSystemFont(12), "#FFFFFF");
    addText(widget, "No data yet", Font.systemFont(11), "#FFFFFF", 2);
    return widget;
  }
  if (model.family === "accessoryCircular") {
    const row = model.rows[0];
    widget.addAccessoryWidgetBackground = true;
    addText(widget, `${row.percentLeft}%`, Font.boldSystemFont(14), "#FFFFFF").centerAlignText();
    addText(widget, row.name, Font.systemFont(9), "#FFFFFF").centerAlignText();
    return widget;
  }
  // accessoryRectangular: one line per provider, plus a stale mark.
  model.rows.forEach((row) => {
    const line = widget.addStack();
    line.centerAlignContent();
    addText(line, row.name, Font.semiboldSystemFont(12), "#FFFFFF");
    line.addSpacer(4);
    line.addImage(barImage(row.percentLeft, "#FFFFFF", 40, 5)).imageSize = new Size(40, 5);
    line.addSpacer(4);
    addText(line, `${row.percentLeft}%`, Font.boldMonospacedSystemFont(12), "#FFFFFF");
    line.addSpacer();
  });
  if (model.stale) addText(widget, "Stale · " + model.updated.replace("Updated ", ""), Font.systemFont(10), "#FFFFFF");
  return widget;
}

async function main() {
  const family = config.widgetFamily || "medium";
  const text = await readSnapshotText();
  const model = buildModel(text, family, new Date(), args.widgetParameter);
  const widget = family.startsWith("accessory") ? renderLockScreen(model) : renderHomeScreen(model);
  widget.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000);
  if (config.runsInWidget) {
    Script.setWidget(widget);
  } else {
    await widget.presentMedium();
  }
  Script.complete();
}

if (typeof ListWidget !== "undefined") {
  await main();
} else if (typeof module !== "undefined") {
  module.exports = {
    parseSnapshot, colorForPercent, updatedLabel, isStale, resetLabel,
    tightestLimit, buildRows, buildModel, inlineText, COLORS,
  };
}
