#!/usr/bin/env python3
"""Corrects the pictures that `docc` writes for a reader with no JavaScript.

    python3 scripts/fix_static_pictures.py <folder of the built site>

`scripts/build_docs.sh` runs this after `docc convert`.

With the flag that puts the text of a page into its HTML, `docc` writes each
page a second time, into a `noscript` element. A browser with no JavaScript
and a search engine read that part. Its `picture` element is wrong:

  - Each `source` has a `src`. In a `picture`, a browser reads `srcset` and
    ignores `src`.
  - That `src` is not the address of the file in the site. It is the path of
    the file in the checkout of the build, in small letters.
  - The `img` has no `src`.

So such a reader gets no picture, and each page that has one holds the path
of the checkout. This was seen with the docc of Xcode 26.6 and of Xcode 27.0.

For each `source` in a `picture`, this script takes the file name from the
wrong `src`, finds the one file with that name under `images/` of the site,
and writes its address as `srcset`, relative to the page. The name is written
as the site has it: a web server tells `A.png` from `a.png`. A name with
`@2x` or `@3x` gets that density. The `img` gets the address of the light
variant as its `src`, or of the first `source` when none is light.

The script changes nothing in a `picture` that is correct already, so it is
safe to run two times, and a later `docc` with no fault passes.

It stops with exit code 1, and changes no file, when:

  - a `source` names a file that is not under `images/`, or more than one
    file under `images/` has that name
  - a `picture` has a form that the script does not know

It reads and writes only `index.html` files under `documentation/` of the
folder that it gets. It uses the standard library only, and no network.
"""

from __future__ import annotations

import os
import re
import sys
from urllib.parse import quote

PICTURE = re.compile(r"<picture>(.*?)</picture>", re.DOTALL)
SOURCE = re.compile(r"<source\b[^>]*?/?>")
IMAGE = re.compile(r"<img\b[^>]*?/?>")
SRC = re.compile(r'\ssrc="([^"]*)"')
SRCSET = re.compile(r'\ssrcset="([^"]*)"')
DENSITY = re.compile(r"@([23])x\.[A-Za-z0-9]+$")


class Stop(Exception):
    """One sentence for the person who runs the build."""


def pictures_of(site: str) -> dict[str, list[str]]:
    """Each file under images/, by its name in small letters."""
    found: dict[str, list[str]] = {}
    images = os.path.join(site, "images")
    for folder, _, names in os.walk(images):
        for name in names:
            path = os.path.relpath(os.path.join(folder, name), site)
            found.setdefault(name.lower(), []).append(path.replace(os.sep, "/"))
    return found


def address(page: str, site: str, wrong: str, pictures: dict[str, list[str]]) -> str:
    """The address of the file that a wrong `src` means, relative to the page."""
    name = wrong.rsplit("/", 1)[-1]
    matches = pictures.get(name.lower(), [])
    where = os.path.relpath(page, site)
    if not matches:
        raise Stop(f"{where} has a picture, {name}, and the site has no file with that name under images/.")
    if len(matches) > 1:
        raise Stop(f"{where} has a picture, {name}, and more than one file under images/ has that name: "
                   + ", ".join(sorted(matches)) + ".")
    depth = os.path.relpath(os.path.dirname(page), site).count(os.sep) + 1
    return "../" * depth + quote(matches[0], safe="/@~-._")


def corrected(block: str, page: str, site: str, pictures: dict[str, list[str]]) -> str:
    """One `picture` element, with each address made correct."""
    where = os.path.relpath(page, site)
    sources = SOURCE.findall(block)
    images = IMAGE.findall(block)
    if len(images) != 1:
        raise Stop(f"{where} has a picture element with {len(images)} img elements. This script knows one.")

    light = None
    first = None
    for tag in sources:
        if SRCSET.search(tag):
            continue
        wrong = SRC.search(tag)
        if not wrong:
            raise Stop(f"{where} has a source element with no src and no srcset: {tag}")
        target = address(page, site, wrong.group(1), pictures)
        density = DENSITY.search(target)
        value = f"{target} {density.group(1)}x" if density else target
        block = block.replace(tag, tag.replace(wrong.group(0), f' srcset="{value}"'), 1)
        first = first or target
        if "prefers-color-scheme: light" in tag:
            light = light or target

    image = images[0]
    if not SRC.search(image):
        target = light or first
        if target is None:
            raise Stop(f"{where} has an img element with no src, and no source element gives one.")
        block = block.replace(image, image.replace("<img", f'<img src="{target}"', 1), 1)
    return block


def main(arguments: list[str]) -> int:
    if len(arguments) != 2:
        print("usage: python3 scripts/fix_static_pictures.py <folder of the built site>", file=sys.stderr)
        return 2
    site = os.path.abspath(arguments[1])
    pages_folder = os.path.join(site, "documentation")
    if not os.path.isdir(pages_folder):
        print(f"fix_static_pictures.py: {site} has no folder documentation. It is not a built site.",
              file=sys.stderr)
        return 1

    pictures = pictures_of(site)
    changes: dict[str, str] = {}
    count = 0
    try:
        for folder, _, names in sorted(os.walk(pages_folder)):
            if "index.html" not in names:
                continue
            page = os.path.join(folder, "index.html")
            with open(page, encoding="utf-8") as file:
                text = file.read()
            if "<picture>" not in text:
                continue

            def replace(match: re.Match[str]) -> str:
                return "<picture>" + corrected(match.group(1), page, site, pictures) + "</picture>"

            new = PICTURE.sub(replace, text)
            if new != text:
                changes[page] = new
                count += sum(1 for a, b in zip(PICTURE.findall(text), PICTURE.findall(new)) if a != b)
    except Stop as stop:
        print(f"fix_static_pictures.py: {stop} No page was changed.", file=sys.stderr)
        return 1

    # Each page is read and corrected before the first one is written, so a
    # fault in one page leaves the whole site as docc made it.
    for page, new in changes.items():
        with open(page, "w", encoding="utf-8") as file:
            file.write(new)
    print(f"    Pictures for a reader with no JavaScript: {count} corrected, on {len(changes)} pages.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
