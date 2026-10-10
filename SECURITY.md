# Security

Plateworks Desqueeze changes photo files on a person's Mac. A problem that
can damage, lose or expose a person's files is a security problem here.

## What the app touches

- **Files.** It reads the top level of the one folder that you give it. It
  writes DNG files in that folder: a tag in a DNG that exists, and a new DNG
  beside each ARW that it converts. It never changes, moves or deletes an
  ARW. It does not read subfolders.
- **The Trash.** It moves three kinds of file to the Trash. The first is the
  backup of a DNG, after the new tag reads back correctly. The second is its
  own hidden work file: after a conversion that failed, and when it finds
  one that an earlier run left. The third is the temporary file that
  exiftool can leave beside that work file. It moves a leftover of an
  earlier run only when it is a regular file, not a folder and not a link.
  It deletes nothing.
- **Three external programs.** It starts exiftool, dnglab and Adobe DNG
  Converter as separate processes, with no shell. It looks for exiftool and
  dnglab in `/opt/homebrew/bin`, then `/usr/local/bin`, then each folder of
  `PATH`. So it starts the program of that name that it finds first. It
  looks for Adobe DNG Converter in the Applications folder. The window
  first asks macOS where the app with Adobe's bundle identifier is.
- **Saved settings.** The window saves one value of its own: the factor of
  the last run.
- **No network.** The window and the command line tool make no network
  request. The MCP server speaks to its client on standard input and
  standard output only. The build of the server fetches its libraries from
  GitHub.
- **No data collection.** No analytics, no log that leaves the Mac.

The app is not sandboxed, because a sandboxed app cannot start the three
programs. It runs with the rights of the person who starts it, and it never
asks for more.

The MCP server changes files when a client calls `desqueeze_run` or
`desqueeze_remove`. It takes one absolute folder path for each call, and it
runs one call at a time. Give it only to a client that you trust with your
photo folders.

## Report a problem

Report a security problem in private, with a security advisory on the GitHub
repo: open the "Security" tab of the repo, and select "Report a
vulnerability". Do not open a public issue for it.

Say what you did, what you expected, and what happened. Give the output of
the command with `--verbose` when you can. Do not attach a photo that you do
not want public.

Only the newest version gets fixes.
