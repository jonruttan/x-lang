/* bitwise.js -- the browser twin of apps/bitwise/gen.x.  Same seeding, same
 * integer geometry in micro-units, same markup, so the gallery page and the
 * x program draw the identical bytes for a name.  gen.x is the definition;
 * this file follows it, and tests/x/specs/apps/bitwise.spec.md holds the
 * digests both must produce (regenerate them with parity.js).
 *
 *     ., .,
 *     {O,O}
 *     (   )
 *      " "
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Bitwise = factory();
}(typeof self !== "undefined" ? self : this, function () {
  "use strict";
  // The data is xon: s-expression forms, one reader for both files.  A form
  // is an array whose head is a symbol ({sym}); strings, integers and nested
  // forms are what the files use.
  function readXon(text) {
    const forms = [], stack = [];
    let i = 0, cur = null;
    const push = (v) => { if (cur) cur.push(v); else forms.push(v); };
    while (i < text.length) {
      const c = text[i];
      if (c === ";") { while (i < text.length && text[i] !== "\n") i++; }
      else if (c === "(") { const f = []; push(f); stack.push(cur); cur = f; i++; }
      else if (c === ")") { cur = stack.pop(); i++; }
      else if (c === '"') {
        let s = ""; i++;
        while (i < text.length && text[i] !== '"') {
          if (text[i] === "\\") { i++; s += ({ n: "\n", t: "\t", r: "\r" })[text[i]] || text[i]; }
          else s += text[i];
          i++;
        }
        i++; push(s);
      }
      else if (/\s/.test(c)) i++;
      else {
        let t = ""; while (i < text.length && !/[\s()"]/.test(text[i])) t += text[i++];
        push(/^-?\d+$/.test(t) ? parseInt(t, 10) : { sym: t });
      }
    }
    return forms;
  }
  const head = (f) => Array.isArray(f) && f[0] && f[0].sym;
  function shapeGlyphs(text) {
    const g = { glyphs: {}, index: {} };
    for (const f of readXon(text)) {
      if (head(f) === "font") { g.family = f[1]; g.upm = f[2]; g.adv = f[3]; g.asc = f[4]; g.desc = f[5]; g.gap = f[6]; }
      else if (head(f) === "glyph") { g.index[f[1]] = f[2]; g.glyphs[f[1]] = f[3]; }
    }
    return g;
  }
  function shapeLangs(text) {
    const langs = {};
    for (const f of readXon(text)) {
      if (head(f) !== "costume") continue;
      const lang = {};
      for (const field of f.slice(2)) {
        const k = head(field), v = field.slice(1);
        lang[k] = ["accent", "secondary", "eyes", "rows", "roles"].includes(k) ? v : v[0];
      }
      langs[f[1]] = lang;
    }
    return langs;
  }
  // In a browser the gallery build injects both texts.  Under node (the
  // parity script) the glyphs come from beside this file, and the costumes
  // from the SAME frozen fixtures the specs load -- both sides must draw
  // from identical inputs for a parity run to mean anything.
  const readText = (rel) => (typeof require === "function") ? require("fs").readFileSync(require("path").join(__dirname, "..", rel), "utf8") : null;
  function fixtureCostumes() {
    if (typeof require !== "function") return "";
    const fs = require("fs"), path = require("path");
    const dir = path.join(__dirname, "../../../tests/x/fixtures/bitwise/costumes");
    return fs.readdirSync(dir).filter((f) => f.endsWith(".xon")).sort()
      .map((f) => fs.readFileSync(path.join(dir, f), "utf8")).join("\n");
  }
  const GLYPHS = shapeGlyphs((typeof BITWISE_GLYPHS_XON !== "undefined") ? BITWISE_GLYPHS_XON : readText("glyphs.xon"));
  const LANGS = shapeLangs((typeof BITWISE_LANGS_XON !== "undefined") ? BITWISE_LANGS_XON : fixtureCostumes());
  const UPM = GLYPHS.upm, ADV = GLYPHS.adv, ASC = GLYPHS.asc, LINE = GLYPHS.asc - GLYPHS.desc + GLYPHS.gap;
  const U = 1000000, INK = "#161a22", PAPER = "#f2f4f7";
  const FONT = "'Roboto Mono','Martian Mono',Menlo,'DejaVu Sans Mono',ui-monospace,monospace";
  const SIGIL = ["., .,", "{O,O}", "(   )", " \" \""], SIGIL_ROLES = ["ii ii", "ieifi", "iiiii", " i i "];
  const OPS = ["xor", "and", "or", "rings", "moire", "prod"], GRIDS = [16, 20, 24, 32];
  const POW10 = [1, 10, 100, 1000, 10000, 100000, 1000000];
  const div = (a, b) => Math.floor(a / b);           // x's integer division, on non-negatives

  // v micro-units -> "d.dd" with d decimals, rounded half-up.
  function fmt(v, d) {
    const dv = POW10[6 - d], q = div(v + div(dv, 2), dv), p = POW10[d];
    return d === 0 ? String(q) : div(q, p) + "." + String(q % p).padStart(d, "0");
  }
  const esc = (t) => String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

  // ---------------------------------------------------------------- seeding
  const K = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];
  function sha256(bytes) {
    const rotr = (x, n) => (x >>> n) | (x << (32 - n));
    const len = bytes.length, bitLen = len * 8;
    const padded = new Uint8Array(((len + 9 + 63) >> 6) << 6);
    padded.set(bytes); padded[len] = 0x80;
    const dv = new DataView(padded.buffer);
    dv.setUint32(padded.length - 8, Math.floor(bitLen / 0x100000000));
    dv.setUint32(padded.length - 4, bitLen >>> 0);
    let H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    const w = new Uint32Array(64);
    for (let off = 0; off < padded.length; off += 64) {
      for (let i = 0; i < 16; i++) w[i] = dv.getUint32(off + i * 4);
      for (let i = 16; i < 64; i++) {
        const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
      }
      let [a, b, c, d, e, f, g, h] = H;
      for (let i = 0; i < 64; i++) {
        const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25), ch = (e & f) ^ (~e & g);
        const t1 = (h + S1 + ch + K[i] + w[i]) >>> 0;
        const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22), maj = (a & b) ^ (a & c) ^ (b & c);
        const t2 = (S0 + maj) >>> 0;
        h = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
      }
      H = [a, b, c, d, e, f, g, h].map((v, i) => (H[i] + v) >>> 0);
    }
    const out = [];
    for (const v of H) out.push(v >>> 24, (v >>> 16) & 255, (v >>> 8) & 255, v & 255);
    return out;
  }
  async function digest(name) {
    const bytes = new TextEncoder().encode(name);
    const subtle = (typeof crypto !== "undefined" && crypto.subtle) ? crypto.subtle : null;
    if (subtle) { try { return Array.from(new Uint8Array(await subtle.digest("SHA-256", bytes))); } catch (e) { /* pure */ } }
    return sha256(bytes);
  }

  function op(o, x, y, a, b, s) {
    switch (o) {
      case 0: return ((x * a) ^ (y * b)) ^ s;
      case 1: return ((x * a) & (y * b)) ^ s;
      case 2: return ((x * a) | (y * b)) ^ s;
      case 3: return (x * x * a + y * y * b) ^ s;
      case 4: return ((x * a + y * b) ^ (x * y)) ^ s;
      default: return ((x * y * a) ^ ((x + y) * b)) ^ s;
    }
  }
  function field(p, n) {
    const half = div(n, 2), rows = [];
    for (let j = 0; j < n; j++) {
      const row = [];
      for (let i = 0; i < n; i++) {
        const x = p.op === 3 ? Math.abs(i - half) : i + p.ox, y = p.op === 3 ? Math.abs(j - half) : j + p.oy;
        const v = op(p.op, x, y, p.a, p.b, p.salt) >>> 0;
        row.push(((v >>> p.bit) & 1) === 1);
      }
      rows.push(row);
    }
    return rows;
  }
  const lit = (rows) => rows.reduce((n, r) => n + r.filter(Boolean).length, 0);
  function formula(o, a, b) {
    switch (o) {
      case 0: return "(x*" + a + ") ^ (y*" + b + ")";
      case 1: return "(x*" + a + ") & (y*" + b + ")";
      case 2: return "(x*" + a + ") | (y*" + b + ")";
      case 3: return "x*x*" + a + " + y*y*" + b;
      case 4: return "(x*" + a + " + y*" + b + ") ^ (x*y)";
      default: return "(x*y*" + a + ") ^ (x+y)*" + b;
    }
  }
  function gateOk(p) {
    const n = p.n, l = lit(field(p, n));
    return l * 100 >= 18 * n * n && l * 100 <= 82 * n * n;
  }
  function params(name, h) {
    const p = {
      name, hue10: div((h[0] * 256 + h[1]) * 7200 + 65536, 131072),
      op: h[2] % 6, bit: 1 + h[3] % 4, a: (h[4] & 7) * 2 + 1, b: (h[5] & 7) * 2 + 1,
      ox: h[6] & 31, oy: h[7] & 31, salt: h[8], n: GRIDS[h[9] % 4],
    };
    for (let step = 0; step < 24 && !gateOk(p); step++) {
      p.bit = 1 + (p.bit % 4);
      if (step % 4 === 3) p.op = (p.op + 1) % 6;
    }
    p.lit = lit(field(p, p.n));
    p.opname = OPS[p.op];
    p.formula = formula(p.op, p.a, p.b) + " >> " + p.bit + " & 1";
    return p;
  }

  // ---------------------------------------------------------------- colour
  const hueStr = (h10) => div(h10, 10) + "." + (h10 % 10);
  const hsl = (h, s, l) => "hsl(" + h + "," + s + "%," + l + "%)";
  const hsl3 = (t) => hsl(String(t[0]), t[1], t[2]);
  function palette(p, lang) {
    const hue = hueStr(p.hue10), acc = lang.accent || null;
    const accent = acc ? hsl3(acc) : hsl(hue, 58, 46);
    return {
      accent,
      deep: acc ? hsl(String(acc[0]), acc[1], div(acc[2] * 65, 100)) : hsl(hue, 55, 30),
      eyes: lang.eyes ? lang.eyes.map(hsl3) : [accent, accent],
      secondary: lang.secondary ? hsl3(lang.secondary) : accent,
    };
  }
  function colour(pal, role) {
    switch (role) {
      case "e": return pal.eyes[0];
      case "f": return pal.eyes[1];
      case "a": return pal.accent;
      case "b": return pal.secondary;
      default: return INK;
    }
  }

  // ---------------------------------------------------------------- the owl
  const glyphList = (s) => Array.from(s);
  const chars = (s) => glyphList(s).length;
  function costume(lang) {
    return [(lang.rows || SIGIL).map(glyphList), (lang.roles || SIGIL_ROLES).map(glyphList)];
  }
  function owl(pal, rows, roles, uid, xU, yU, k) {
    const used = [], groups = {}, ks = fmt(k, 4);
    rows.forEach((row, r) => {
      const base = yU + (ASC + r * LINE) * k;
      row.forEach((ch, c) => {
        if (ch === " ") return;
        if (!used.includes(ch)) used.push(ch);
        const role = roles[r][c];
        (groups[role] = groups[role] || []).push('<use href="#' + uid + '-' + GLYPHS.index[ch] +
          '" transform="translate(' + fmt(xU + c * ADV * k, 2) + ',' + fmt(base, 2) + ') scale(' + ks + ',-' + ks + ')"/>');
      });
    });
    const defs = used.map((ch) => '<path id="' + uid + '-' + GLYPHS.index[ch] + '" d="' + GLYPHS.glyphs[ch] + '"/>').join("");
    return "<defs>" + defs + "</defs>" + ["i", "e", "f", "a", "b"].map((r) =>
      groups[r] ? '<g fill="' + colour(pal, r) + '">' + groups[r].join("") + "</g>" : "").join("");
  }
  function owlIn(pal, lang, uid, x, y, bw, bh) {
    const [rows, roles] = costume(lang), n = rows.length, cols = Math.max(...rows.map((r) => r.length));
    const sizeU = Math.min(div(bh * UPM * U, n * LINE), div(bw * UPM * U, cols * ADV));
    const k = div(sizeU, UPM), wU = cols * ADV * k, hU = n * LINE * k;
    return owl(pal, rows, roles, uid, x * U + div(bw * U - wU, 2), y * U + div(bh * U - hU, 2), k);
  }
  function bitfield(p, cols, rowsN, cellU, color, opacity) {
    const rows = field(p, Math.max(cols, rowsN)), inset = div(cellU * 3, 10), ws = fmt(cellU - 2 * inset, 1);
    const cells = [];
    for (let j = 0; j < rowsN; j++) for (let i = 0; i < cols; i++) if (rows[j][i])
      cells.push('<rect x="' + fmt(i * cellU + inset, 1) + '" y="' + fmt(j * cellU + inset, 1) + '" width="' + ws + '" height="' + ws + '"/>');
    return '<g fill="' + color + '" fill-opacity="' + opacity + '">' + cells.join("") + "</g>";
  }

  // ---------------------------------------------------------------- formats
  const svgOpen = (w, h, title) => '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h +
    '" viewBox="0 0 ' + w + " " + h + '" role="img" aria-label="' + esc(title) + '">';
  function fmtMark(p, pal, lang, uid) {
    const n = p.n;
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="512" height="512" role="img" aria-label="Bitwise, ' +
      esc(p.name) + '">' + bitfield(p, n, n, div(100 * U, n), pal.accent, "0.22") + owlIn(pal, lang, uid, 6, 8, 88, 84) + "</svg>";
  }
  function fmtAvatar(p, pal, lang, uid) {
    return svgOpen(512, 512, "Bitwise, " + p.name) + '<rect width="512" height="512" fill="' + PAPER + '"/>' +
      bitfield(p, 16, 16, 32 * U, pal.accent, "0.14") + owlIn(pal, lang, uid, 40, 56, 432, 400) + "</svg>";
  }
  const words = (t) => t.split(" ").filter((w) => w !== "");
  const glyphTake = (s, n) => glyphList(s).slice(0, n).join("");
  const rstrip = (s, cs) => { let e = s.length; while (e > 0 && cs.includes(s[e - 1])) e--; return s.slice(0, e); };
  function wrap(text, width) {
    let lines = [], cur = "";
    for (const w of words(text)) {
      if (cur !== "" && chars(cur) + 1 + chars(w) > width) { lines.push(cur); cur = w; }
      else cur = cur === "" ? w : cur + " " + w;
    }
    if (cur !== "") lines.push(cur);
    if (lines.length > 4) lines = [lines[0], lines[1], lines[2], rstrip(glyphTake(lines[3], width - 1), ",;: ") + "…"];
    return lines;
  }
  const text = (x, y, size, fill, extra, body) => '<text x="' + x + '" y="' + y + '" font-family="' + FONT +
    '" font-size="' + size + '"' + extra + ' fill="' + fill + '">' + esc(body) + "</text>";
  function fmtBanner(p, pal, lang, tagline, kind, uid) {
    const x = 560, name = p.name, nlen = chars(name), fs = nlen <= 10 ? 96 : (nlen <= 14 ? 72 : 56);
    let y = 356; const tag = wrap(tagline, 42).map((l) => { const t = text(x, y, 26, INK, "", l); y += 36; return t; }).join("");
    const col = lang.logo ? lang.logo : "hue " + div(p.hue10, 10) + "&#176;";
    return svgOpen(1280, 640, name + ", with Bitwise") + '<rect width="1280" height="640" fill="' + PAPER + '"/>' +
      bitfield(p, 40, 20, 32 * U, pal.accent, "0.09") + owlIn(pal, lang, uid, 60, 90, 440, 460) +
      text(x, 200, 20, pal.deep, ' letter-spacing="4"', (kind === "" ? "an x project" : kind).toUpperCase()) +
      text(x, 300, fs, INK, ' font-weight="700"', name) + tag +
      (lang.reference ? text(x, 524, 24, pal.deep, ' xml:space="preserve"', lang.reference) : "") +
      '<text x="' + x + '" y="580" font-family="' + FONT + '" font-size="15" fill="' + pal.deep + '">plumage  ' + esc(p.formula) + "   " + col + "</text></svg>";
  }

  function renderWith(h, name, fmt_, tagline, kind, uid) {
    uid = uid || "o"; tagline = tagline || ""; kind = kind || "";
    const p = params(name, h), lang = LANGS[name] || {}, pal = palette(p, lang);
    p.costume = lang.mascot || lang.logo || "";
    p.reference = lang.reference || "";
    let svg;
    if (fmt_ === "mark") svg = fmtMark(p, pal, lang, uid);
    else if (fmt_ === "avatar") svg = fmtAvatar(p, pal, lang, uid);
    else if (fmt_ === "banner") svg = fmtBanner(p, pal, lang, tagline, kind, uid);
    else throw new Error("bitwise: unknown format " + fmt_);
    return { svg, params: p, palette: pal };
  }
  async function render(name, fmt_, tagline, kind, uid) { return renderWith(await digest(name), name, fmt_, tagline, kind, uid); }
  // "LENGTH:FNV1A32" over the UTF-8 bytes, as gen.x's bitwise-fingerprint.
  function fingerprint(s) {
    const bytes = new TextEncoder().encode(s);
    let h = 2166136261;
    for (const b of bytes) h = Math.imul(h ^ b, 16777619) >>> 0;
    return bytes.length + ":" + h.toString(16).padStart(8, "0");
  }
  return { render, renderWith, digest, sha256, fingerprint, params, palette, costume, field, hueStr, readXon, LANGS, GLYPHS, OPS, GRIDS, SIGIL };
}));
