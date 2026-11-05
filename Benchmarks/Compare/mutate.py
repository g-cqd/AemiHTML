#!/usr/bin/env python3
"""Writes N mutated HTML files for the differential test: the inputs of html5lib's tree-construction tests, each cut, spliced with tags and markup pieces, or flipped at random (seeded, so a failure repeats).
usage: mutate.py TREE_CONSTRUCTION_DIR OUT_DIR N [SEED]"""
import os, random, sys

src, out, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
rng = random.Random(int(sys.argv[4]) if len(sys.argv) > 4 else 1)
seeds = []
for name in sorted(os.listdir(src)):
    if not name.endswith(".dat"):
        continue
    for block in open(os.path.join(src, name), "rb").read().split(b"\n#data\n"):
        data = block.split(b"\n#errors\n")[0]
        if data.startswith(b"#data\n"):
            data = data[6:]
        if b"#document-fragment" in block.split(b"\n#errors\n")[0]:
            continue
        seeds.append(data)
names = ["a", "b", "i", "p", "div", "span", "table", "tr", "td", "th", "tbody", "thead", "caption", "colgroup", "col", "select", "option", "optgroup", "button", "form", "ul", "ol", "li", "dl", "dt", "dd",
         "h1", "h3", "pre", "textarea", "title", "style", "script", "noscript", "template", "svg", "math", "mi", "mtext", "annotation-xml", "foreignObject", "desc", "font", "frameset", "frame", "html", "head",
         "body", "base", "meta", "link", "br", "hr", "img", "input", "nobr", "em", "strong", "code", "u", "s", "small", "big", "tt", "applet", "marquee", "object", "iframe", "noembed", "noframes", "xmp",
         "plaintext", "ruby", "rt", "rb", "details", "summary", "dialog", "address", "center", "menu", "listing", "isindex", "image", "keygen", "param", "source", "track", "wbr", "embed", "fieldset", "legend", "label"]
pieces = ["<!--", "-->", "<![CDATA[", "]]>", "<!DOCTYPE html>", "<!doctype html public \"x\">", "&amp;", "&lt", "&#0;", "&#x80;", "&notit;", "&", "\x00", "\r\n", "\r", " ", "\t", "\n", "'", "\"", "=", "/", ">", "<",
          "</", "<!", "x", "text", "-->", "--!>", "<!-->", " id=a", " class=b", " encoding=text/html", " color=red", " xlink:href=u", " definitionurl=x", " viewbox=0", "/>"]
def tag():
    n = rng.choice(names)
    r = rng.random()
    if r < 0.55:
        return "<" + n + (rng.choice(pieces) if rng.random() < 0.2 else "") + ">"
    if r < 0.9:
        return "</" + n + ">"
    return "<" + n + "/>"
def mutate(data: bytes) -> bytes:
    text = data.decode("utf-8", "replace")
    for _ in range(rng.randint(1, 4)):
        at = rng.randint(0, len(text))
        k = rng.random()
        if k < 0.45:
            text = text[:at] + tag() + text[at:]
        elif k < 0.65:
            text = text[:at] + rng.choice(pieces) + text[at:]
        elif k < 0.8:
            end = min(len(text), at + rng.randint(1, 6))
            text = text[:at] + text[end:]
        elif k < 0.9 and len(text) > 2:
            other = rng.randint(0, len(text) - 1)
            text = text[:at] + text[other:other + rng.randint(1, 20)] + text[at:]
        else:
            text = text[:at]
    return text.encode("utf-8")
os.makedirs(out, exist_ok=True)
written = 0
while written < count:
    data = mutate(rng.choice(seeds))
    # Two documented differences, not tested here: processing instructions (the 2026 standard) and selectedcontent.
    if b"<?" in data or b"selectedcontent" in data.lower():
        continue
    open(os.path.join(out, "%06d.html" % written), "wb").write(data)
    written += 1
print(written, "files from", len(seeds), "seeds")
