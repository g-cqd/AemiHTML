#!/bin/sh
# Fetches public web pages for the benchmark into the cache (never committed): `~/Library/Caches/AemiHTMLCorpus/pages`, or AEMIHTML_CORPUS. What a page is depends on the day and on the server's
# idea of the client, so the benchmark prints the sizes it ran on; pages that fail to download are skipped.
set -u
cache="${AEMIHTML_CORPUS:-$HOME/Library/Caches/AemiHTMLCorpus}/pages"
mkdir -p "$cache"
while read -r name url; do
    [ -f "$cache/$name.html" ] || curl -sL -m 40 -A "Mozilla/5.0 (Macintosh) AemiHTML-benchmark" "$url" -o "$cache/$name.html" || true
done <<'LIST'
whatwg-parsing https://html.spec.whatwg.org/multipage/parsing.html
whatwg-single https://html.spec.whatwg.org/
whatwg-syntax https://html.spec.whatwg.org/multipage/syntax.html
wikipedia-markdown https://en.wikipedia.org/wiki/Markdown
wikipedia-html https://en.wikipedia.org/wiki/HTML
wikipedia-swift https://en.wikipedia.org/wiki/Swift_(programming_language)
mdn-html https://developer.mozilla.org/en-US/docs/Web/HTML
github-repo https://github.com/swiftlang/swift-markdown
hackernews https://news.ycombinator.com/
rust-lang https://www.rust-lang.org/
python-htmlparser https://docs.python.org/3/library/html.parser.html
bbc-news https://www.bbc.com/news
stackoverflow https://stackoverflow.com/questions
apple https://www.apple.com/
nytimes https://www.nytimes.com/
cppreference https://en.cppreference.com/w/cpp/container/vector
LIST
find "$cache" -name '*.html' -size -2k -delete
ls -l "$cache" | awk 'NR>1 {print $5, $9}'
