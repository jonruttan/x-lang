// node parity.js [--write] -- the browser twin's renderings for eight names in
// every format.  --write puts them under tests/x/fixtures/bitwise/expected/,
// where tests/x/specs/apps/bitwise-parity-*.spec.md compares gen.x's bytes
// against them; without it, prints "NAME FMT LENGTH:FNV1A32".  A design change
// regenerates the fixtures: change gen.x, port it here, --write, run the specs.
const fs = require("fs"), path = require("path");
const B = require("./bitwise.js");
const TAG = "A tagline with enough words in it to wrap past four lines of the banner column, so the fourth line ends with an ellipsis rather than running off the edge of the picture";
const NAMES = ["x-lang", "x-engine-rust", "x-python", "x-logo", "x-awk", "x-r5rs", "x-sweet", "hello, world"];
const slug = (s) => s.replace(/[^A-Za-z0-9]+/g, "-");
const write = process.argv.includes("--write");
const dir = path.resolve(__dirname, "../../../tests/x/fixtures/bitwise/expected");
(async () => {
  if (write) fs.mkdirSync(dir, { recursive: true });
  for (const name of NAMES) for (const fmt of ["mark", "avatar", "banner"]) {
    const { svg } = await B.render(name, fmt, TAG, "a language on x-lang");
    if (write) fs.writeFileSync(path.join(dir, slug(name) + "-" + fmt + ".svg"), svg);
    else console.log(name + " " + fmt + " " + B.fingerprint(svg));
  }
  if (write) console.log("wrote " + NAMES.length * 3 + " fixtures to " + dir);
})();
