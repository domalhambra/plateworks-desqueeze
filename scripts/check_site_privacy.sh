#!/bin/bash
# Check what the built documentation site loads and saves.
#
#   scripts/check_site_privacy.sh [folder]
#
# The folder is a site that scripts/build_docs.sh made. The default is
# build/docs. scripts/build_docs.sh runs this check at its end, so each
# build has it: on this Mac, and on the runner that publishes the site.
#
# The privacy page of the site, the article Privacy, says what the site
# loads and what it saves in a browser. DocC makes the scripts of the site,
# and they change with Xcode. So the page is true for a build only when this
# check passes for that build. The check reads files only. It asks no
# network.
#
# What fails the check:
#
#   1. A file from another host. The site has no host of its own in its
#      files, so each host is another host. The letters of a tag and of an
#      attribute can be in any case.
#      - In the HTML: a `src` or a `poster` with a host, a `srcset` with a
#        host in any place of it, an `object` tag with a host in its `data`,
#        a `base` tag with a host, and a `link` tag with a host. A `link`
#        tag whose `rel` is exactly `canonical` or `alternate` loads
#        nothing, and passes.
#      - In the HTML, the CSS and the SVG files: a `url(` or an `@import`
#        with a host.
#      - In an SVG file: an `href` or a `src` with a host, and a script.
#      - In the data files: a picture or a video of an article with a host.
#      - In theme-settings.json: an address with a host.
#   2. An inline script in a page, other than the one that DocC writes with
#      the base path of the site. Rules 3 to 5 read the script files only,
#      so they cannot speak for an inline script.
#   3. In the scripts: `document.cookie`, `indexedDB`, `sendBeacon` or
#      `serviceWorker`. A word in quotes, such as "indexedDB" in a list of
#      keywords of the syntax colors, is not a use. One of those words, or
#      `cookie`, `localStorage` or `sessionStorage`, as a name in brackets,
#      such as window["localStorage"], is a use and fails.
#   4. A key of the browser storage that is not in the list below. An empty
#      key and a key with a space are keys too.
#   5. A use of `localStorage` or `sessionStorage` that the check cannot
#      read, and a storage module that it cannot read. Then a person reads
#      the scripts: docs/changing-things.md has the steps. One of the two
#      words in quotes, or in an error message of plain words, is not a use.
#   6. A page that holds the path of the checkout of a build. DocC writes
#      that path, in small letters, into the picture tags that a browser with
#      no script reads. scripts/fix_static_pictures.py corrects those tags
#      before this check runs.
#
# What the check reports and does not judge:
#
#   - The hosts that the data files and the scripts name. Those are links
#     for a person, license notes and XML namespaces. With
#     DOCS_SOURCE_BASE_URL set, each API page has a link to its source on
#     GitHub, and the report counts them.
#
# How it finds a storage key. The scripts are minified, so it reads text:
#
#   a. A call with the key as text: sessionStorage.setItem("scrollPosition",
#   b. Each text with `.setting.` in it: "docs.setting.preferredLanguage"
#   c. The storage module. One module wraps the two storages, puts a prefix
#      before a key, and exports objects. The check reads the prefix, the
#      names of the exports and the storage of each one. Then it reads each
#      call of an export. For a key that is a short name, it reads the value
#      of that name in the same file: ec="sidebar".
#
# What it can miss, so a pass is not a full proof. Each of these passed in a
# trial on a changed copy of a site:
#
#   - A cookie that a script reaches through another name: d=document, then
#     d.cookie.
#   - A request that a script makes to another host: `fetch`, a picture that
#     a script makes with `new Image().src`, a `WebSocket`. The check prints
#     the hosts that the scripts name as text, and does not judge them.
#   - An export of the storage module that a script takes apart into a name
#     of its own, and then calls by that name.
#   - A key that a script builds from parts.
#   - A call of the export with no prefix whose key is a variable. The check
#     prints such a call and does not fail: the keys of those calls are
#     written in full today, and rule b finds them.
#   - A script that reaches the storage with no use of the words
#     `localStorage` and `sessionStorage`.
#   - An event handler in a tag, such as `onload`, and an address that
#     starts with `javascript:`.
#   - A file of a kind that the check does not read. It reads HTML, CSS, SVG
#     and script files, the data files, and theme-settings.json.
#   - What the host sets when it serves a page. The check reads files.
#
# It can also fail with no cause: a short name that has two values in one
# file gives two keys, and one of them is none.
#
# When a new Xcode gives another key or another form, the check fails. That
# is the signal: read the scripts, then change the article Privacy and the
# list below in the same commit.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
site="${1:-$root/build/docs}"

# The keys that the article Privacy speaks for: the storage, then the key.
# "local-read" is a key that the scripts read and never write. It is an
# older name of the color scheme.
known_keys="local developer.setting.preferredColorScheme
local developer.setting.preferredLocale
local docs.setting.preferredLanguage
local developer.setting.sidebar
local developer.setting.navigator-hidden-large
local-read docs.setting.preferredColorScheme
session scrollPosition
session developer.setting.navigator.state"

if [ ! -d "$site" ] || [ ! -d "$site/js" ]; then
    echo "check_site_privacy.sh: no built site is at $site. Run scripts/build_docs.sh first." >&2
    exit 1
fi

failures=0
fail() {
    echo "check_site_privacy.sh: $*" >&2
    failures=$((failures + 1))
}

# grep, where "no match" is an answer and not an error.
search() {
    grep "$@" || [ $? -eq 1 ]
}

# Each file of one kind, one on each line.
files_of() {
    find "$site" -type f -name "$1" | sort
}

# The storage that the list has for a key, or nothing.
listed_storage() {
    local storage key
    while read -r storage key; do
        if [ "$key" = "$1" ]; then
            echo "$storage"
            return
        fi
    done <<< "$known_keys"
}

host='(https?:)?//'
quote="[\"']?"
name='[A-Za-z_$][A-Za-z0-9_$]*'
text_form='^"[^"]*"$'
name_form='^[A-Za-z_$][A-Za-z0-9_$]*$'

echo "The check of what the site loads and saves: ${site#"$root"/}"

# 1. Files from another host.
html_count="$(files_of '*.html' | wc -l | tr -d ' ')"
css_count="$(files_of '*.css' | wc -l | tr -d ' ')"
svg_count="$(files_of '*.svg' | wc -l | tr -d ' ')"
js_count="$(files_of '*.js' | wc -l | tr -d ' ')"

loads="$(
    search -rHoiE --include='*.html' "[[:space:]](src|poster)=$quote[[:space:]]*$host[^\"' >]*" "$site"
    # A `srcset` holds more than one address. A host in any place of it.
    search -rHoiE --include='*.html' "[[:space:]]srcset=(\"[^\"]*$host[^\"]*\"|'[^']*$host[^']*'|$host[^ >]*)" "$site"
    search -rHoiE --include='*.html' "<object[[:space:]]([^>]*[[:space:]])?data=$quote[[:space:]]*$host[^\"' >]*" "$site"
    search -rHoiE --include='*.html' "<base[[:space:]]([^>]*[[:space:]])?href=$quote[[:space:]]*$host[^\"' >]*" "$site"
    # `rel="alternate stylesheet"` loads a style, so only the exact word passes.
    search -rHoiE --include='*.html' "<link[^>]*href=$quote[[:space:]]*$host[^>]*>" "$site" \
        | search -viE "rel=(\"(canonical|alternate)\"|'(canonical|alternate)'|(canonical|alternate)[[:space:]/>])"
    search -rHoiE --include='*.html' --include='*.css' --include='*.svg' "url\\([[:space:]]*$quote$host[^)]*\\)|@import[^;]*$host[^;]*" "$site"
    # In an SVG file. `xmlns` is a name and no address, and it does not match.
    search -rHoiE --include='*.svg' "[[:space:]:](href|src)=$quote[[:space:]]*$host[^\"' >]*|<script" "$site"
)"
if [ -n "$loads" ]; then
    while IFS= read -r line; do
        fail "a file from another host: ${line#"$site"/}"
    done <<< "$loads"
fi

# In the data files a slash can have a backslash before it. A picture or a
# video is an object with `traits` and `url`, in either order. The object
# has no brace inside, so the search takes one object at a time.
media=""
if [ -d "$site/data" ]; then
    media="$(search -rhoE '\{[^{}]*"url":"(https?:)?\\?/\\?/[^"]*"[^{}]*\}' "$site/data" \
        | search -E '"traits":\[' \
        | search -oE '"url":"(https?:)?\\?/\\?/[^"]*"' | sort -u)"
fi
if [ -n "$media" ]; then
    while IFS= read -r line; do
        fail "a picture or a video from another host in the data files: $line"
    done <<< "$media"
fi

theme=""
if [ -f "$site/theme-settings.json" ]; then
    theme="$(search -oE '"(https?:)?\\?/\\?/[^"]*"' "$site/theme-settings.json" | sort -u)"
fi
if [ -n "$theme" ]; then
    while IFS= read -r line; do
        fail "theme-settings.json names a host, and the pages can load from it: $line"
    done <<< "$theme"
fi
echo "  Files from another host: $([ -z "$loads$media$theme" ] && echo none || echo found) ($html_count HTML files, $css_count CSS files, $svg_count SVG files)."

# 2. Inline scripts. Each `script` tag with no `src` is one. DocC writes one
# in each page: var baseUrl = "/the-base-path/". A file that has more inline
# scripts than scripts of that form has one that the check cannot read.
inline_all="$(search -rHoiE --include='*.html' '<script[^>]*>' "$site" \
    | search -viE '<script[^>]*[[:space:]]src=' \
    | sed -E 's/:<[sS][cC][rR][iI][pP][tT][^:]*$//' | sort)"
inline_docc="$(search -rHoE --include='*.html' '<script>var baseUrl = "/([^/"<>][^"<>]*)?"</script>' "$site" \
    | sed -E 's/:<script>var baseUrl = [^:]*$//' | sort)"
inline_other="$(comm -23 <(echo "$inline_all") <(echo "$inline_docc") | search -v '^$' | sort -u)"
if [ -n "$inline_other" ]; then
    while IFS= read -r file; do
        fail "an inline script that DocC did not write, and the check does not read inline scripts: ${file#"$site"/}"
    done <<< "$inline_other"
fi
echo "  Inline scripts other than DocC's own: $([ -z "$inline_other" ] && echo none || echo found)."

# 3. Other ways to save or to send.
senders=""
for word in 'document\.cookie' 'indexedDB' 'sendBeacon' 'serviceWorker'; do
    if [ "$word" = 'document\.cookie' ]; then
        pattern="$word"
    else
        pattern="(^|[^\"'A-Za-z0-9_\$])$word"
    fi
    hits="$(search -rlE --include='*.js' "$pattern" "$site")"
    if [ -n "$hits" ]; then
        while IFS= read -r file; do
            fail "a script uses ${word//\\/}: ${file#"$site"/}"
            senders="found"
        done <<< "$hits"
    fi
done
# The same things through a name in brackets: window["localStorage"].
brackets="$(search -rHoE --include='*.js' "\\[[\"'](cookie|indexedDB|sendBeacon|serviceWorker|localStorage|sessionStorage)[\"']\\]" "$site" | sort -u)"
if [ -n "$brackets" ]; then
    while IFS= read -r line; do
        fail "a script reaches a cookie or a storage through a name in brackets: ${line#"$site"/}"
        senders="found"
    done <<< "$brackets"
fi
echo "  Cookie, database, beacon, service worker: ${senders:-none} ($js_count scripts)."

# 4 and 5. The browser storage. The keys that were found: the storage, a
# tab, the key, one on each line. A key can be empty or have a space, so no
# space splits the two.
found_keys=""
add_key() {
    found_keys="$found_keys$1"$'\t'"$2"$'\n'
}

# a. A call with the key as text.
direct="$(search -rhoE --include='*.js' '(localStorage|sessionStorage)\.(getItem|setItem|removeItem)\("[^"]*"' "$site" | sort -u)"
if [ -n "$direct" ]; then
    while IFS= read -r call; do
        storage="local"
        case "$call" in sessionStorage*) storage="session" ;; esac
        key="${call#*\(\"}"
        add_key "$storage" "${key%\"}"
    done <<< "$direct"
fi

# b. Each text with `.setting.` and a name after it. The storage is the one
# of the list: the text alone does not say it.
full="$(search -rhoE --include='*.js' '"[A-Za-z]+\.setting\.[A-Za-z0-9._-]+"' "$site" | sort -u)"
if [ -n "$full" ]; then
    while IFS= read -r text; do
        key="${text//\"/}"
        storage="$(listed_storage "$key")"
        storage="${storage%-read}"
        add_key "${storage:-unknown}" "$key"
    done <<< "$full"
fi

# c. The storage module.
prefixes="$(search -rhoE --include='*.js' '"[A-Za-z]+\.setting\."' "$site" | sort -u)"
module_text=""
if [ -n "$prefixes" ]; then
    if [ "$(echo "$prefixes" | wc -l | tr -d ' ')" != 1 ]; then
        fail "the scripts have more than one storage prefix, and the check knows the form with one: $(echo $prefixes)"
    fi
    prefix="$(echo "$prefixes" | head -1)"
    prefix="${prefix//\"/}"

    # The exports of the module, directly before the prefix:
    #   n.d(t,{IG:function(){return l},Ud:function(){return o}});...const i="developer.setting."
    exports_text="$(search -rhoE --include='*.js' "$name\\.d\\([a-z],\\{[^;]*\\}\\);[^\"]{0,200}\"${prefix//./\\.}\"" "$site")"
    # The storage of each name of the module:
    #   const o=a(window.localStorage),s=a(window.sessionStorage),l=r(o),c=r(s)
    storages_text="$(search -rhoE --include='*.js' "(const|let|var) $name=$name\\(window\\.(localStorage|sessionStorage)\\)(,$name=$name\\([A-Za-z_\$.]+\\))+" "$site")"
    module_text="$exports_text $storages_text"

    if [ -z "$exports_text" ] || [ -z "$storages_text" ] \
        || [ "$(echo "$exports_text" | wc -l | tr -d ' ')" != 1 ] || [ "$(echo "$storages_text" | wc -l | tr -d ' ')" != 1 ]; then
        fail "the check cannot read the storage module of these scripts, so it cannot name each key. Read the scripts by hand."
    else
        # name=function(argument), one on each line.
        assignments="$(echo "$storages_text" | sed -E 's/^(const|let|var) //' | tr ',' '\n')"
        kind_of_variable() {
            # local, session, local-prefix, session-prefix, or nothing.
            local variable="$1" argument raw
            argument="$(echo "$assignments" | awk -F'[=()]' -v v="$variable" '$1 == v { print $3; exit }')"
            case "$argument" in
                window.localStorage) echo "local" ;;
                window.sessionStorage) echo "session" ;;
                "") ;;
                *)
                    raw="$(echo "$assignments" | awk -F'[=()]' -v v="$argument" '$1 == v { print $3; exit }')"
                    case "$raw" in
                        window.localStorage) echo "local-prefix" ;;
                        window.sessionStorage) echo "session-prefix" ;;
                    esac
                    ;;
            esac
        }

        # EXPORT:function(){return VARIABLE}, or EXPORT:()=>VARIABLE.
        exports="$(echo "$exports_text" | search -oE "$name:(function\\(\\)\\{return $name\\}|\\(\\)=>$name)" | sed -E 's/:(function\(\)\{return |\(\)=>)/ /; s/\}$//')"
        if [ -z "$exports" ]; then
            fail "the check cannot read the exports of the storage module. Read the scripts by hand."
        fi
        while read -r export variable; do
            [ -n "$export" ] || continue
            kind="$(kind_of_variable "$variable")"
            if [ -z "$kind" ]; then
                fail "the check cannot tell which storage the export $export of the storage module uses."
                continue
            fi
            storage="${kind%-prefix}"
            before=""
            case "$kind" in *-prefix) before="$prefix" ;; esac

            # Each call of the export, file by file: a short name has its
            # value in the same file.
            while IFS= read -r file; do
                calls="$(search -oE "\\.${export//\$/\\\$}\\.(get|set|remove|getItem|setItem|removeItem)\\([^,)]*" "$file" | sort -u)"
                [ -n "$calls" ] || continue
                while IFS= read -r call; do
                    argument="${call#*\(}"
                    values=""
                    readable=""
                    if [[ "$argument" =~ $text_form ]]; then
                        # A key as text. It can be empty.
                        values="${argument//\"/}"
                        readable="yes"
                    elif [[ "$argument" =~ $name_form ]]; then
                        values="$(search -oE "(^|[^A-Za-z0-9_\$.])${argument//\$/\\\$}=\"[^\"]*\"" "$file" | sed -E 's/^[^"]*"//; s/"$//' | sort -u)"
                        [ -z "$values" ] || readable="yes"
                    fi
                    if [ -n "$readable" ]; then
                        while IFS= read -r value; do
                            add_key "$storage" "$before$value"
                        done <<< "$values"
                    elif [ -n "$before" ]; then
                        fail "the check cannot read the key of a call that saves with the prefix $prefix: $call in ${file#"$site"/}"
                    else
                        echo "  A call with a key that the check cannot read, not judged: $call in ${file#"$site"/}"
                    fi
                done <<< "$calls"
            done < <(files_of '*.js')
        done <<< "$exports"
    fi
fi

# 5. Each use of the two words must be one of these forms: a word in quotes,
# a word in a text of plain words (an error message), a call with the key as
# text, or a part of the storage module.
all_js="$(find "$site" -type f -name '*.js' -exec cat {} +)"
strip() {
    sed -E \
        -e "s/[\"'](localStorage|sessionStorage)[\"']/_/g" \
        -e 's/"[A-Za-z0-9 ]* (localStorage|sessionStorage)[A-Za-z0-9 ]*"/_/g' \
        -e 's/(window\.)?(localStorage|sessionStorage)\.(getItem|setItem|removeItem)\("[^"]*"/_/g' \
        -e 's/\(window\.(localStorage|sessionStorage)\)/(_)/g' \
        -e 's/=localStorage\)/=_)/g'
}
unread="$(echo "$all_js" | strip | search -oE '.{0,60}(localStorage|sessionStorage).{0,60}')"
if [ -n "$unread" ]; then
    while IFS= read -r line; do
        fail "a use of the browser storage that the check cannot read: $line"
    done <<< "$unread"
fi
# A storage that is given to a function is read only for the storage module.
given_total="$(echo "$all_js" | search -oE '\(window\.(localStorage|sessionStorage)\)|=localStorage\)' | wc -l | tr -d ' ')"
given_module="$(echo "$module_text" | search -oE '\(window\.(localStorage|sessionStorage)\)' | wc -l | tr -d ' ')"
default_parameter="$(echo "$all_js" | search -oE "function $name\\($name=localStorage\\)\\{return\\{getItem" | wc -l | tr -d ' ')"
if [ "$given_total" != "$((given_module + default_parameter))" ]; then
    fail "the scripts give a browser storage to a function outside the storage module, and the check cannot read what that function saves."
fi

# The answer: each key, and whether the list has it. A key that is empty or
# has a space is shown in quotes.
found_keys="$(printf '%s' "$found_keys" | search -v '^$' | sort -u)"
echo "  Keys of the browser storage:"
if [ -z "$found_keys" ]; then
    echo "    none"
else
    while IFS=$'\t' read -r storage key; do
        shown="$key"
        case "$key" in "" | *[[:space:]]*) shown="\"$key\"" ;; esac
        listed="$(listed_storage "$key")"
        if [ -z "$key" ] || [ -z "$listed" ]; then
            echo "    $storage  $shown  NOT IN THE LIST"
            fail "a key of the browser storage is not in the list of this script: $shown ($storage storage). The article Privacy does not speak for it."
        elif [ "${listed%-read}" != "$storage" ]; then
            echo "    $storage  $shown  IN THE LIST AS ${listed%-read}"
            fail "the key $shown is in the $storage storage, and the list of this script has it in the ${listed%-read} storage."
        else
            echo "    $storage  $shown$([ "$listed" = local-read ] && echo "  (read, never written)")"
        fi
    done <<< "$found_keys"
fi
while read -r storage key; do
    if ! printf '%s\n' "$found_keys" | awk -F'\t' -v key="$key" '$2 == key { found = 1 } END { exit !found }'; then
        echo "  In the list and not in this site: $key. The article Privacy can say less."
    fi
done <<< "$known_keys"

# The report, not judged: hosts that the data files and the scripts name.
if [ -d "$site/data" ]; then
    source_links="$(search -rhoE '"https?:\\?/\\?/github\.com(\\?/[^"\\/]+){2}\\?/blob\\?/[^"]*"' "$site/data" | wc -l | tr -d ' ')"
    echo "  Links to the sources on GitHub in the data files, not judged: $source_links."
    hosts="$(search -rhoE '"https?:\\?/\\?/[^"\\/]+' "$site/data" | sed -E 's/^"https?:\\?\/\\?\///' | sort | uniq -c | awk '{ printf "%s%s (%s)", sep, $2, $1; sep = ", " }')"
    echo "  Hosts that the data files name, as links for a person: ${hosts:-none}."
fi
script_hosts="$(echo "$all_js" | search -oE '"https?://[^"/]+' | sed -E 's/^"https?:\/\///' | sort | uniq -c | awk '{ printf "%s%s (%s)", sep, $2, $1; sep = ", " }')"
echo "  Hosts that the scripts name, as text: ${script_hosts:-none}."

# The path of the checkout. DocC writes it, in small letters, into the
# picture tags that a browser with no script reads: there it stands in place
# of the address of the file, so the picture does not load, and the public
# site names a folder of the machine that built it.
# scripts/fix_static_pictures.py corrects those tags before this check. The
# search does not look at the case of the letters. It finds the path of this
# checkout, and the end of the path of a catalog, which a site from another
# machine has too.
checkout_pages="$(search -rliF --include='*.html' -e "${root#/}" -e '.docc/resources/' "$site" | wc -l | tr -d ' ')"
if [ "$checkout_pages" -gt 0 ]; then
    fail "$checkout_pages page(s) hold the path of the checkout of a build. scripts/build_docs.sh runs scripts/fix_static_pictures.py to correct them: this site did not get that step, or docc writes the path in a new place."
fi
echo "  Pages that hold the path of the checkout of a build: $checkout_pages."

if [ "$failures" -gt 0 ]; then
    echo "check_site_privacy.sh: $failures finding(s). The article Privacy is not true for this site. docs/changing-things.md has the steps." >&2
    exit 1
fi
echo "  The check passed."
