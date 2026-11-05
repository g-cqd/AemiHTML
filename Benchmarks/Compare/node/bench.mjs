// parse5's full parse (the HTML parser of jsdom and many tools), nodes and text bytes counted by an explicit stack; the best round's CPU time of the process.
// usage: node bench.mjs DIR [--rounds N]
import fs from "node:fs";
import { parse } from "parse5";
const args = process.argv.slice(2);
const rounds = Number(args.includes("--rounds") ? args[args.indexOf("--rounds") + 1] : 3);
const pages = fs.readdirSync(args[0]).sort().map((n) => fs.readFileSync(`${args[0]}/${n}`, "utf8"));
const total = pages.reduce((s, p) => s + Buffer.byteLength(p), 0);
const cpu = () => { const u = process.cpuUsage(); return (u.user + u.system) / 1e6; };
function run() {
  let nodes = 0, text = 0;
  for (const page of pages) {
    const stack = [parse(page)];
    while (stack.length) {
      const node = stack.pop();
      nodes++;
      if (node.nodeName === "#text") text += Buffer.byteLength(node.value);
      const children = node.content ? node.content.childNodes : node.childNodes;
      if (children) for (const child of children) stack.push(child);
    }
  }
  return [nodes, text];
}
let counts = run(), best = Infinity;
for (let r = 0; r < rounds; r++) { const start = cpu(); counts = run(); best = Math.min(best, cpu() - start); }
console.log(JSON.stringify({ engine: "parse5", what: "dom", pages: pages.length, bytes: total, seconds: best, mbps: total / best / 1e6, tokens: counts[0], text_bytes: counts[1] }));
