#!/bin/sh
# Fetches the tree-construction tests as web-platform-tests keeps them (the .dat files moved there in 2026-06 and are edited in place: new files for processing instructions and the search element, new cases in the old ones)
# into a cache outside the repository, at a pinned commit. Only html/syntax/parsing/resources is checked out.
# usage: Scripts/fetch-wpt-tree.sh        (the cache is ~/Library/Caches/AemiHTMLCorpus, or AEMIHTML_CORPUS)
set -eu
commit=fc7c47fcb9172a216914879460e98018348ee3c5
cache="${AEMIHTML_CORPUS:-$HOME/Library/Caches/AemiHTMLCorpus}"
work="$cache/wpt"
mkdir -p "$cache"
if [ ! -d "$work/.git" ]; then
    git clone --quiet --filter=blob:none --no-checkout https://github.com/web-platform-tests/wpt.git "$work"
fi
git -C "$work" sparse-checkout init --cone
git -C "$work" sparse-checkout set html/syntax/parsing/resources
git -C "$work" fetch --quiet --depth 1 origin "$commit" 2>/dev/null || true
git -C "$work" checkout --quiet "$commit"
rm -rf "$cache/wpt-tree-construction"
mkdir -p "$cache/wpt-tree-construction"
cp "$work"/html/syntax/parsing/resources/*.dat "$cache/wpt-tree-construction/"
echo "web-platform-tests $commit: $(ls "$cache/wpt-tree-construction" | wc -l | tr -d ' ') .dat files in $cache/wpt-tree-construction"
