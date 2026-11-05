"""Damages slices of the corpus pages at random (replaced, inserted and deleted bytes, markup openers, truncation) for the tokenizer differential.
usage: mutate-pages.py WORKDIR SEED COUNT   (writes WORKDIR/in/pNNNNNN.html)"""
import os,random,glob,sys
W=sys.argv[1]; random.seed(int(sys.argv[2]))
pages=sorted(glob.glob(os.path.expanduser("~/Library/Caches/AemiHTMLCorpus/pages/*")))
data=[open(p,"rb").read() for p in pages]
chars=list(b'<>&"\'/=!-?[]\x00 \n\t;#xX0aA') + [0xC3,0xA9,0xF0,0x9F,0x98,0x80,0xFF,0xED,0xA0]
n=0
while n<int(sys.argv[3]):
    d=random.choice(data); a=random.randrange(0,max(1,len(d)-4000)); s=bytearray(d[a:a+random.choice([300,1000,4000])])
    for _ in range(random.choice([1,2,4,8,16])):
        if not s: break
        k=random.random(); i=random.randrange(len(s))
        if k<0.4: s[i]=random.choice(chars)
        elif k<0.7: s.insert(i,random.choice(chars))
        elif k<0.85: del s[i:i+random.randint(1,12)]
        else: s[i:i]=random.choice([b"<!--",b"<![CDATA[",b"<script>",b"</script",b"<textarea>",b"&amp",b"&#x",b"<?",b"<!DOCTYPE",b"<a b='",b'<a b="',b"]]>",b"--!>"])
    if random.random()<0.2: s=s[:random.randrange(len(s)+1)]
    open(f"{W}/in/p{n:06d}.html","wb").write(bytes(s)); n+=1
