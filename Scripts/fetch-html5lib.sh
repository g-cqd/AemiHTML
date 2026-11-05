#!/bin/sh
# Fetches the html5lib tests (MIT) that the tokenizer is checked against into a cache outside the repository, at a pinned commit.
# usage: Scripts/fetch-html5lib.sh        (the cache is ~/Library/Caches/AemiHTMLCorpus, or AEMIHTML_CORPUS)
set -eu
commit=c5495c539ca8a79c3c5107f5f14010bcff9a35d5
cache="${AEMIHTML_CORPUS:-$HOME/Library/Caches/AemiHTMLCorpus}"
mkdir -p "$cache"
if [ ! -d "$cache/html5lib-tests/.git" ]; then
    git clone --quiet https://github.com/html5lib/html5lib-tests.git "$cache/html5lib-tests"
fi
git -C "$cache/html5lib-tests" fetch --quiet origin "$commit" 2>/dev/null || true
git -C "$cache/html5lib-tests" checkout --quiet "$commit"
# The tree-construction tests moved to web-platform-tests in 2026-06; the last copy html5lib held, in the data format the harness reads, is pinned here.
tree=224991ec10db04f056a89eed8b0bd8695fd2950e
rm -rf "$cache/tree-construction-src"
mkdir -p "$cache/tree-construction-src"
git -C "$cache/html5lib-tests" archive "${tree}^" tree-construction | tar -x -C "$cache/tree-construction-src"
echo "html5lib-tests $commit and tree-construction (pre-move, $tree) in $cache"
