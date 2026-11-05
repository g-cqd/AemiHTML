"""Python's html.parser tokenizer (the standard library's, which is not the HTML5 tokenization algorithm) counting its events; the best round's thread CPU time.
usage: bench.py DIR [--rounds N]"""
import json, os, sys, time
from html.parser import HTMLParser

args = sys.argv[1:]
rounds = int(args[args.index("--rounds") + 1]) if "--rounds" in args else 3
pages = [open(os.path.join(args[0], n), encoding="utf-8", errors="replace").read() for n in sorted(os.listdir(args[0]))]
total = sum(len(p.encode()) for p in pages)

class Counter(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tokens = 0
        self.text = 0
    def handle_starttag(self, tag, attrs): self.tokens += 1
    def handle_startendtag(self, tag, attrs): self.tokens += 1
    def handle_endtag(self, tag): self.tokens += 1
    def handle_data(self, data): self.tokens += 1; self.text += len(data.encode())
    def handle_comment(self, data): self.tokens += 1
    def handle_decl(self, decl): self.tokens += 1
    def handle_pi(self, data): self.tokens += 1

def run():
    tokens = text = 0
    for page in pages:
        parser = Counter()
        parser.feed(page)
        parser.close()
        tokens += parser.tokens
        text += parser.text
    return tokens, text

best = float("inf")
for _ in range(rounds):
    start = time.thread_time()
    tokens, text = run()
    best = min(best, time.thread_time() - start)
print(json.dumps({"engine": "python-html.parser", "what": "tokens", "pages": len(pages), "bytes": total, "seconds": best, "mbps": total / best / 1e6, "tokens": tokens, "text_bytes": text}))
