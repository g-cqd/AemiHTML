// The tree of every file of a directory in parse5, one line per node, in the format of the Swift and Rust dumpers.
// usage: AEMIHTML_DUMP_DIR=out node tree.mjs DIR
import { parse } from "parse5";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";

const esc = (s) => s.replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t");
const spaces = { "http://www.w3.org/2000/svg": "svg", "http://www.w3.org/1998/Math/MathML": "math" };
const prefixes = { "http://www.w3.org/1999/xlink": "xlink ", "http://www.w3.org/XML/1998/namespace": "xml ", "http://www.w3.org/2000/xmlns/": "xmlns " };

function dump(root) {
  const lines = [];
  const stack = [];
  for (let i = root.childNodes.length - 1; i >= 0; i--) stack.push([root.childNodes[i], 0]);
  while (stack.length) {
    const [node, depth] = stack.pop();
    const pad = " ".repeat(depth);
    let kids = node.childNodes ?? [];
    switch (node.nodeName) {
      case "#text": lines.push(`${pad}T ${esc(node.value)}`); break;
      case "#comment": lines.push(`${pad}C ${esc(node.data)}`); break;
      case "#documentType": lines.push(`${pad}D ${node.name}`); break;
      default: {
        const attrs = node.attrs.map((a) => {
          let prefix = a.namespace ? (prefixes[a.namespace] ?? "") : "";
          if (a.namespace === "http://www.w3.org/2000/xmlns/" && a.name === "xmlns") prefix = "";
          return `${prefix}${a.name}=${esc(a.value)}`;
        }).sort();
        lines.push(`${pad}E ${spaces[node.namespaceURI] ?? ""} ${node.tagName} ${attrs.join(" \u0001 ")}`);
        if (node.content) {
          lines.push(`${pad} TC`);
          for (let i = kids.length - 1; i >= 0; i--) stack.push([kids[i], depth + 1]);
          const inner = node.content.childNodes;
          for (let i = inner.length - 1; i >= 0; i--) stack.push([inner[i], depth + 2]);
          continue;
        }
      }
    }
    for (let i = kids.length - 1; i >= 0; i--) stack.push([kids[i], depth + 1]);
  }
  return lines.join("\n") + "\n";
}

const dir = process.argv[2];
const out = process.env.AEMIHTML_DUMP_DIR ?? "/tmp";
for (const name of readdirSync(dir).sort()) {
  const html = readFileSync(`${dir}/${name}`, "utf8");
  writeFileSync(`${out}/${name}.parse5.tree.txt`, dump(parse(html, { scriptingEnabled: false })));
}
