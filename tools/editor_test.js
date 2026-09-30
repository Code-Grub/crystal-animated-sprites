// Tests for the pure logic in tools/editor.html.   node tools/editor_test.js
"use strict";
const fs = require("fs");
const html = fs.readFileSync(__dirname + "/editor.html", "utf8");
const script = html.split("<script>")[1].split("</script>")[0];
const win = {};
new Function("window", script)(win);          // no `document`: only the pure logic registers
const L = win.__editorLogic;

let passed = 0, failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log("PASS  " + name); }
  catch (e) { failed++; console.log("FAIL  " + name + "\n      " + e.message); }
}
function eq(a, b, msg) {
  const x = JSON.stringify(a), y = JSON.stringify(b);
  if (x !== y) throw new Error((msg || "values differ") + ": expected " + y + ", got " + x);
}

// 4x4 pic.  0 = white, 3 = black.  alpha: 1 opaque, 0 transparent.
//  w w 3 w        states:  t t . o        (t transparent white, o opaque white)
//  w 3 3 w                 t . . o
//  w w w w                 t t o o
//  3 3 3 3                 . . . .
const px = "00303300" + "00003333";
const alpha = L.alphaFrom("0011" + "0011" + "0011" + "1111");
const W = 4;

test("flood stays inside one state by default", () => {
  eq(L.flood("0000", 2, L.alphaFrom("0011"), 0).sort(), [0, 1]);
});

test("flood covers the whole connected white area when told to ignore state", () => {
  const all = L.flood("0000", 2, L.alphaFrom("0011"), 0, true).sort();
  eq(all, [0, 1, 2, 3]);
});

test("flood across states still stops at non-white pixels", () => {
  // white, black, white in a row: the black pixel separates them
  eq(L.flood("030", 3, L.alphaFrom("011"), 0, true), [0]);
});

test("flood from a non-white pixel is empty", () => {
  eq(L.flood(px, W, alpha, 2), []);
});

test("apply only changes white pixels", () => {
  const a = L.alphaFrom("1111");
  L.apply(a, "0123", { 0: "clear", 1: "clear", 3: "clear" });
  eq(Array.from(a), [0, 1, 1, 1]);
});

test("runs round trip and merge neighbours", () => {
  const edits = { 4: "clear", 5: "clear", 6: "keep", 9: "clear" };
  const runs = L.toRuns(edits, 4);
  eq(runs, [[1, 0, 1, "clear"], [1, 2, 2, "keep"], [2, 1, 1, "clear"]]);
  eq(L.fromRuns(runs, 4), edits);
});

test("lua export has the shape lib/edits.lua expects", () => {
  const lua = L.toLua({ front: { 6: { all: { 4: "clear" }, 2: { 5: "keep" } } }, back: { 151: { 0: "keep" } } }, { 6: 4 });
  if (!/\[6\] = \{ all = \{ \{ 1, 0, 0, "clear" \} \}, \[2\] = \{ \{ 1, 1, 1, "keep" \} \} \},/.test(lua)) throw new Error(lua);
  if (!/\[151\] = \{ \{ 0, 0, 0, "keep" \} \},/.test(lua)) throw new Error(lua);
  if (!/^return \{/m.test(lua)) throw new Error("no return table");
});


// ---------------------------------------------------------------- page flow
// Drives the real page code against a stubbed DOM and a tiny synthetic sprite.
function pageHarness() {
  const ids = {}, winH = {}, docH = {}, store = {};
  const ctx = () => new Proxy({}, { get: (t, k) => (typeof t[k] !== "undefined" ? t[k] : () => {}), set: (t, k, v) => { t[k] = v; return true; } });
  const el = (id) => ids[id] || (ids[id] = {
    id, className: "", textContent: "", value: "", innerHTML: "", children: [], style: {}, checked: false, disabled: false, _h: {},
    addEventListener(t, f) { this._h[t] = f; }, getContext: ctx, appendChild(c) { this.children.push(c); }, select() {},
    getBoundingClientRect() { return { left: 0, top: 0, width: this.width || 100, height: this.height || 100 }; },
  });
  el("backdrop").value = "blue"; el("brush").value = "1"; el("search").value = ""; el("mark").checked = true;
  const radios = [{ value: "frame", checked: true, disabled: false }, { value: "all", checked: false, disabled: false }];
  const document = { getElementById: el, createElement: () => el("c" + Math.random()), addEventListener(t, f) { docH[t] = f; },
    querySelector: () => radios.find((r) => r.checked), querySelectorAll: () => radios, execCommand() {} };
  const w = {
    addEventListener(t, f) { winH[t] = f; },
    EDITOR: { names: ["Testmon"], edits: { front: {}, back: {} }, sprites: { 1: { w: 6,
      // a white 2x2 hole inside a black ring; the border is background
      front: [{ f: 0, px: "000000" + "033330" + "030030" + "030030" + "033330" + "000000",
                a: "000000" + "011110" + "011110" + "011110" + "011110" + "000000" }],
      back: { px: "0".repeat(48 * 48), a: "0".repeat(48 * 48) } } } },
  };
  new Function("window", "document", "localStorage", "navigator", "confirm", script)(
    w, document, { getItem: (k) => store[k] || null, setItem: (k, v) => { store[k] = v; } }, {}, () => true);
  const canvas = el("main");
  const scale = Math.max(4, Math.floor(560 / 6));
  return {
    el, radios, key: (k) => docH.keydown({ key: k, target: {} }),
    click(x, y) { canvas.width = canvas.height = 6 * scale; canvas._h.mousedown({ clientX: x * scale + 1, clientY: y * scale + 1 }); winH.mouseup(); },
    out: () => el("out").value,
  };
}

test("fill transparent sets the clicked white area, not a flip", () => {
  const p = pageHarness();
  p.key("4");
  p.click(2, 2);
  if (!/\[1\] = \{ \[0\] = \{ \{ 2, 2, 3, "clear" \}, \{ 3, 2, 3, "clear" \} \} \},/.test(p.out())) throw new Error(p.out());
  p.click(2, 2);                                   // filling again leaves it transparent
  if (!/\{ 2, 2, 3, "clear" \}/.test(p.out())) throw new Error("second fill undid the first:\n" + p.out());
});

test("fill opaque restores what a fill transparent cleared, leaving no edits", () => {
  const p = pageHarness();
  p.key("4"); p.click(2, 2);
  p.key("5"); p.click(2, 2);
  if (/front = \{\s*\[1\]/.test(p.out())) throw new Error("edits should be gone:\n" + p.out());
});

test("fill stays inside one state unless 'across states' is ticked", () => {
  const p = pageHarness();
  p.key("4"); p.click(2, 2);                        // the hole is now transparent
  p.key("3"); p.click(2, 2);                        // paint one pixel opaque again: mixed states
  p.key("5");
  p.click(3, 3);                                    // fill opaque, same state only
  if (!/"clear"/.test(p.out())) throw new Error("same-state fill should leave the pixel at (2,2) alone:\n" + p.out());
  p.el("across").checked = true;
  p.click(3, 3);                                    // fill opaque across states: the whole hole
  if (/front = \{\s*\[1\]/.test(p.out())) throw new Error("across-state fill should make the whole hole opaque:\n" + p.out());
});

test("fill on a black pixel does nothing", () => {
  const p = pageHarness();
  p.key("4"); p.click(1, 1);
  if (/front = \{\s*\[1\]/.test(p.out())) throw new Error(p.out());
});

test("flip region still toggles", () => {
  const p = pageHarness();
  p.key("1"); p.click(2, 2);
  if (!/"clear"/.test(p.out())) throw new Error(p.out());
  p.click(2, 2);
  if (/front = \{\s*\[1\]/.test(p.out())) throw new Error("second flip should restore:\n" + p.out());
});

console.log("\n" + passed + " passed, " + failed + " failed");
process.exit(failed ? 1 : 0);
