#!/bin/sh
# The Encoding Standard's data (labels, and the index of every legacy encoding), into the corpus cache. generate-encodings.py reads it.
set -eu
cache="${AEMIHTML_CORPUS:-$HOME/Library/Caches/AemiHTMLCorpus}/encoding"
mkdir -p "$cache"
curl -sSfL -o "$cache/encodings.json" https://encoding.spec.whatwg.org/encodings.json
curl -sSfL -o "$cache/indexes.json" https://encoding.spec.whatwg.org/indexes.json
echo "$cache"
