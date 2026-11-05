"""Lexbor (a C HTML5 parser, via selectolax) parsing each page to its DOM and walking it, nodes and text bytes counted; the best round's thread CPU time.
usage: dom.py DIR [--rounds N]"""
import json, os, sys, time
from selectolax.lexbor import LexborHTMLParser

args = sys.argv[1:]
rounds = int(args[args.index("--rounds") + 1]) if "--rounds" in args else 3
pages = [open(os.path.join(args[0], n), "rb").read() for n in sorted(os.listdir(args[0]))]
total = sum(len(p) for p in pages)

def run():
    nodes = text = 0
    for page in pages:
        tree = LexborHTMLParser(page.decode("utf-8", errors="replace"))
        for node in tree.root.traverse(include_text=True):
            nodes += 1
            if node.tag == "-text":
                text += len((node.text_content or "").encode())
    return nodes, text

best = float("inf")
for _ in range(rounds):
    start = time.thread_time()
    nodes, text = run()
    best = min(best, time.thread_time() - start)
print(json.dumps({"engine": "lexbor", "what": "dom", "pages": len(pages), "bytes": total, "seconds": best, "mbps": total / best / 1e6, "tokens": nodes, "text_bytes": text}))
