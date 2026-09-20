#!/usr/bin/env bash
# Parse-checks every changed or new .luau file with the real luau binary (never the shell).
L=/c/Users/mali7/.rokit/tool-storage/luau-lang/luau/0.738.0/luau.exe
if [ ! -x "$L" ]; then
	echo "luau binary missing: $L"
	exit 1
fi
cd "C:/1000 Hidden Objects" || exit 1
bad=0
for f in $(git diff --name-only -- '*.luau') $(git ls-files --others --exclude-standard -- 'src/*.luau'); do
	out=$(timeout 10 "$L" "$f" 2>&1 | head -1)
	case "$out" in
		*"attempt to index nil"*|*"attempt to call"*|"") ;;
		*) echo "== $f: $out"; bad=1 ;;
	esac
done
echo "parse done (problems: $bad)"
