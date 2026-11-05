#!/usr/bin/env python3
"""Classifies the trees three parsers made of the same files: which agree. Files are DIR/NAME.{aemi,html5ever,parse5}.tree.txt, the inputs are INPUT_DIR/NAME.
Two agreeing against one is the evidence; "h5==p5 [select]" is html5ever and parse5 still following the "in select" modes that the standard dropped in 2026 (AemiHTML follows the standard).
usage: classify.py DIR INPUT_DIR"""
import collections, os, sys
os.chdir(sys.argv[1])
c=collections.Counter(); ex=collections.defaultdict(list)
for f in sorted(os.listdir('.')):
    if not f.endswith('.aemi.tree.txt'): continue
    b=f[:-14]
    a=open(f,'rb').read(); h=open(b+'.html5ever.tree.txt','rb').read(); p=open(b+'.parse5.tree.txt','rb').read()
    src=open(sys.argv[2]+'/'+b,'rb').read().lower()
    sel=b'select' in src
    key=('aemi==h5 ' if a==h else '')+('aemi==p5 ' if a==p else '')+('h5==p5' if h==p else '')
    key=(key.strip() or 'all differ')+(' [select]' if sel else '')
    c[key]+=1; ex[key].append(b)
for k,v in c.most_common(): print(v,k, ex[k][:6] if v<600 else '')
