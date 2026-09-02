// node build.js [index.json] -- inline glyphs, costumes, the twin and the
// project index into gallery.tmpl.html -> build/bitwise/gallery.html.
// The index comes from `x -l bitwise -- --all` (build/bitwise/index.json);
// without one the flock is the costume list, taglines empty.
const fs = require("fs"), path = require("path");
const here = __dirname, root = path.resolve(here, "../../..");
const out = path.join(root, "build", "bitwise", "gallery.html");
const indexPath = process.argv[2] || path.join(root, "build", "bitwise", "index.json");
const safe = (t) => t.replace(/<\/(script)/gi, "<\\/$1");   // only </script ends a script block
const glyphs = fs.readFileSync(path.join(here, "../glyphs.json"), "utf8");
const langs = fs.readFileSync(path.join(here, "../langs.json"), "utf8");
const js = fs.readFileSync(path.join(here, "bitwise.js"), "utf8");
let projects;
if (fs.existsSync(indexPath)) {
  projects = JSON.parse(fs.readFileSync(indexPath, "utf8")).map((p) => ({ name: p.name, kind: p.kind, tagline: p.tagline }));
} else {
  projects = Object.keys(JSON.parse(langs)).map((name) => ({ name, kind: "", tagline: "" }));
  console.warn("build.js: no " + indexPath + "; flock has no taglines (run: x -l bitwise -- --all)");
}
const html = fs.readFileSync(path.join(here, "gallery.tmpl.html"), "utf8")
  .replace("/*@GLYPHS@*/", () => "window.BITWISE_GLYPHS = " + safe(glyphs) + ";\nwindow.BITWISE_LANGS = " + safe(langs) + ";")
  .replace("/*@BITWISE_JS@*/", () => safe(js))
  .replace("/*@PROJECTS@*/", () => safe(JSON.stringify(projects)));
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, html);
console.log(out, html.length, "bytes,", projects.length, "projects");
