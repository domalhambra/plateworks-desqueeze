#!/bin/bash
# Build the documentation site into build/docs/.
#
#   scripts/build_docs.sh
#
# The site is made by DocC, with the `docc` that ships with Xcode. The package
# gets no dependency for it. Two steps:
#
#   1. The compiler writes the symbol graph of DesqueezeCore: its public API
#      and its documentation comments.
#   2. `docc convert` joins the symbol graph with the articles of the catalog,
#      Sources/DesqueezeCore/DesqueezeCore.docc, and writes a static site.
#
# A warning from docc is an error here: a link to an article or a symbol that
# does not exist must not reach the published site.
#
# Then the script writes two small pages of its own. Each one sends a person
# on with a relative link, so it holds under any base path:
#
#   index.html          The address of the site, to the first page.
#   privacy/index.html  The address /privacy/, to the article Privacy. Each
#                       Plateworks property has its privacy page there. The
#                       script stops when the built site has no such article.
#
# Variables, all optional:
#
#   DOCS_HOSTING_BASE_PATH  The path under which the site is served. The
#                           default is plateworks-desqueeze, for a GitHub
#                           Pages site of a repo with that name. Set it to an
#                           empty value for a site at the root of its host.
#   DOCS_SOURCE_BASE_URL    The address of the source files on GitHub, for
#                           example https://github.com/OWNER/REPO/blob/main.
#                           When it is set, each API page gets a link to its
#                           source line. With no value, there is no link.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
catalog="$root/Sources/DesqueezeCore/DesqueezeCore.docc"
output="$root/build/docs"
work="$root/build/docs-work"
module="DesqueezeCore"

# No colon: an empty value is a value, and means the root of the host.
base_path="${DOCS_HOSTING_BASE_PATH-plateworks-desqueeze}"
base_path="${base_path#/}"
base_path="${base_path%/}"

if ! docc="$(xcrun --find docc 2>/dev/null)" || [ ! -x "$docc" ]; then
    echo "build_docs.sh: docc was not found. It ships with Xcode." >&2
    echo "Install Xcode, then select it: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi
if [ ! -d "$catalog" ]; then
    echo "build_docs.sh: the catalog is not at $catalog" >&2
    exit 1
fi

# A clean start. The three folders are this script's own, under build/.
serve="$root/build/docs-serve"
rm -rf "$output" "$work" "$serve"
mkdir -p "$work/symbols"

echo "1/2 The symbol graph of $module"
# A build folder of its own: the flags differ from those of a plain
# `swift build`, so the two would rebuild each other's files in .build/.
swift build --package-path "$root" --scratch-path "$work/swiftpm" --target "$module" \
    -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc "$work/symbols"

arguments=(
    convert "$catalog"
    --additional-symbol-graph-dir "$work/symbols"
    --output-path "$output"
    --fallback-display-name "$module"
    --fallback-bundle-identifier "org.plateworks.desqueeze.$module"
    --transform-for-static-hosting
    --warnings-as-errors
)
if [ -n "$base_path" ]; then
    arguments+=(--hosting-base-path "$base_path")
fi
# With this flag each page holds its title and its text as HTML, so a reader
# with no JavaScript, and a search engine, get the page. The flag is marked
# experimental, so it is used only when this docc has it.
if "$docc" convert --help 2>/dev/null | grep -q -- "--experimental-transform-for-static-hosting-with-content"; then
    arguments+=(--experimental-transform-for-static-hosting-with-content)
else
    echo "    This docc cannot put the text of a page into its HTML. The pages need JavaScript."
fi
if [ -n "${DOCS_SOURCE_BASE_URL-}" ]; then
    arguments+=(--checkout-path "$root" --source-service github --source-service-base-url "$DOCS_SOURCE_BASE_URL")
fi

echo "2/2 docc convert"
"$docc" "${arguments[@]}"

# The address of the site with nothing after it has no page of its own. Send
# it to the first page. The link is relative, so it holds under any base path.
start="documentation/$(echo "$module" | tr '[:upper:]' '[:lower:]')/"
cat > "$output/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Plateworks Desqueeze documentation</title>
<meta http-equiv="refresh" content="0; url=$start">
<link rel="canonical" href="$start">
</head>
<body>
<p><a href="$start">Plateworks Desqueeze documentation</a></p>
</body>
</html>
EOF

# The address /privacy/ sends a person to the article Privacy. The link goes
# up one folder first, so it is relative too. With no page for the article,
# the address would send a person to nothing: stop.
article="${start}privacy/"
if [ ! -f "$output/${article}index.html" ]; then
    echo "build_docs.sh: the built site has no page for the article Privacy, so privacy/index.html would point to nothing." >&2
    exit 1
fi
mkdir -p "$output/privacy"
cat > "$output/privacy/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Plateworks Desqueeze privacy</title>
<meta http-equiv="refresh" content="0; url=../$article">
<link rel="canonical" href="../$article">
</head>
<body>
<p><a href="../$article">Plateworks Desqueeze privacy</a></p>
</body>
</html>
EOF

# A link at build/docs-serve/<base path> that points at the site, so a plain
# web server can show it at the address that the pages expect.
address="http://127.0.0.1:8000/$start"
if [ -n "$base_path" ]; then
    mkdir -p "$serve/$(dirname "$base_path")"
    ln -s "$output" "$serve/$base_path"
    address="http://127.0.0.1:8000/$base_path/$start"
else
    serve="$output"
fi

pages="$(find "$output/data/documentation" -name '*.json' | wc -l | tr -d ' ')"
size="$(du -sh "$output" | cut -f1 | tr -d ' ')"
echo
echo "The site is in build/docs/: $pages pages, $size."
echo "To look at it, start a web server on this Mac, from the root of the repo:"
echo "    python3 -m http.server --bind 127.0.0.1 --directory \"${serve#"$root"/}\" 8000"
echo "Then open $address"
echo "Stop the server with Control-C. If port 8000 is in use, give another number in both places."
echo
echo "For a preview that follows each change to an article:"
echo "    xcrun docc preview Sources/$module/$module.docc --additional-symbol-graph-dir build/docs-work/symbols --fallback-display-name $module --fallback-bundle-identifier org.plateworks.desqueeze.$module --output-path build/docs-preview"
echo "docc prints the address, on localhost."
