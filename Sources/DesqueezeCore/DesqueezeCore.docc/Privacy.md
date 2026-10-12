# Privacy

Desqueeze collects nothing.

## The app

- **No account, no analytics, no crash report, no advertisement.**
- **No network connection.** The app makes none, so it has no update check.
  exiftool and dnglab, the two programs that do the file work, make none in
  a run.
- **Your files.** The app reads and changes files only in the folder that
  you choose. A file that the app discards goes to the Trash of the Mac.
  <doc:WhatHappensToYourFiles> has each rule.
- **One setting of its own.** The app saves the last squeeze factor on the
  Mac, and no other value.
- **Two settings of macOS.** macOS saves two more for the app, as it does
  for each app. They are the place and size of the window, and the size of
  the folder dialog.
- **The first open.** This item is about macOS and not about the app. When
  you open a downloaded app the first time, macOS checks it, and macOS can
  contact Apple for that.

## The command line tool and the MCP server

The same is true for `desqueeze` and `desqueeze-mcp`: no network
connection, and nothing collected.

The MCP server talks only to the program that started it, through standard
input and standard output. What that program sends to its own service is
the matter of that program.

## The website and the download

This website is the documentation of Desqueeze. The download is a disk
image on the Releases page of the repo on GitHub.

- **No cookie, no analytics, no form.**
- **No file from another host.** Each page loads its files from this
  website only.
- **Three things in your browser.** The website saves them in the browser,
  and they stay there:
  - Display settings, for example the color scheme and the width of the
    page list.
  - The scroll position, for the session.
  - The state of the page list, for the session: the page, the open items,
    and its filter, with the text that you type in it.
- **GitHub hosts the website and the download.** GitHub keeps server logs,
  which have the IP address of a visitor, and it counts the downloads of
  each file. For what GitHub does with that data, read
  [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

## Contact

For a question about this page, write to
[dom@plateworks.org](mailto:dom@plateworks.org).

Last updated 2026-10-12.
