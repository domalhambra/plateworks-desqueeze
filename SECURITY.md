# Security

Plateworks Desqueeze changes photo files on a person's Mac. A problem that
can damage, lose or expose a person's files is a security problem here.

## What the app touches

- **Files.** It reads the top level of the one folder that you give it. It
  writes DNG files in that folder: a tag in a DNG that exists, and a new DNG
  beside each ARW that it converts. It never changes an ARW and never
  deletes one. It moves an ARW only to the Trash, and only on your request
  for one run. It does not read subfolders.
- **Your originals, on request.** With the box of the window ticked, or
  with `--trash-originals`, a run moves each ARW that it converted to the
  Trash. It does so only after the DNG passed a check, and only when the
  ARW is the file that was converted and the DNG is the file that this run
  made. The option is off unless you turn it on for that run, and nothing
  saves it. The MCP server has no such option, so an agent cannot remove
  your originals through the server. An agent that has a shell can start
  the command line tool with the flag.
- **The Trash.** Besides an original on request, it moves three kinds of
  file to the Trash. The first is the
  backup of a DNG, after the new tag reads back correctly. The second is its
  own hidden work file: after a conversion that failed, and when it finds
  one that an earlier run left. The third is the temporary file that
  exiftool can leave beside that work file. It moves a leftover of an
  earlier run only when it is a regular file, not a folder and not a link.
  It deletes nothing.
- **One run in a folder at a time.** A run holds an advisory lock on the
  folder until it ends: `flock` on the folder itself. The lock makes no
  file, and it goes when the run ends or the program ends. A second run in
  the same folder does not start and changes nothing: from the window, the
  command line tool or the MCP server. Without the lock, the second run
  would take the first run's work file for a leftover, and send it to the
  Trash. A scan and a dry run take no lock. On a volume that gives no such
  lock, the run goes on without one, and its result says so with a note.
  Any other error of the lock call stops the run before it reads a file. The lock does not stop another program:
  only Desqueeze asks for it.
- **Three external programs.** It starts exiftool, dnglab and Adobe DNG
  Converter as separate processes, with no shell. It looks for exiftool and
  dnglab in `/opt/homebrew/bin`, then `/usr/local/bin`, then each folder of
  `PATH`. So it starts the program of that name that it finds first. It
  looks for Adobe DNG Converter in the Applications folder. The window
  first asks macOS where the app with Adobe's bundle identifier is.
- **Saved settings.** The window saves one value of its own: the factor of
  the last run. It never saves the box that moves the originals.
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
runs one call at a time. It never moves an original ARW: no tool has an
argument for that, and a call that carries one is refused. Give the server
only to a client that you trust with your photo folders.

## Report a problem

Report a security problem in private, with a security advisory on the GitHub
repo: open the "Security" tab of the repo, and select "Report a
vulnerability". Do not open a public issue for it.

Say what you did, what you expected, and what happened. Give the output of
the command with `--verbose` when you can. Do not attach a photo that you do
not want public.

Only the newest version gets fixes.

## For the maintainer

The report path above needs private vulnerability reporting. GitHub has it
off for a new repo. When the GitHub repo is made, switch it on in the
security settings of the repo: "Private vulnerability reporting". Until
then, the "Report a vulnerability" button is not there.
