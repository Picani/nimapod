import asyncdispatch, os, parseopt, sets, strformat, tables

import nimapod/[common, download]


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# Making the CLI

type
  Params = object
    ## The CLI parameters
    dest: string
    dryRun: bool
    verbose: bool
    ignore: bool


proc writeHelp() =
  echo appName, " ", appVersion
  echo """
Download pictures from NASA Astronomy Picture Of the Day (APOD) and put
them into a hierarchy of folders sorted by date.
For now, use the DEMO_KEY api key, which offers a very limited number
of requests.

USAGE: apod_downloader [OPTION] destination

Argument:
  destination     The root of the folders hierarchy

Options:
  -h, --help      Show this help and exit
  -V, --version   Show version information
  -v, --verbose   Be verbose
  -n, --dry-run   Print what would be downloaded and exit
  -i, --ignore    Print the ignored dates and exit
"""

proc writeVersion() =
  echo appName, " ", appVersion


proc cli(): Params =
  result.dryRun = false
  result.verbose = false

  if paramCount() == 0:
    writeHelp()
    quit(0)

  for kind, key, val in getopt():
    case kind:
    of cmdArgument:
      result.dest = key
    of cmdLongOption, cmdShortOption:
      case key:
      of "h", "help":
        writeHelp()
        quit(0)
      of "V", "version":
        writeVersion()
        quit(0)
      of "v", "verbose":
        result.verbose = true
      of "n", "dry-run":
        result.dryRun = true
      of "i", "ignore":
        result.ignore = true
      else:
        discard
    else:
      discard

  if result.dest == "":
    writeLine stderr, "Error: no destination provided."
    quit(1)


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# The main procedure

proc main(params: Params) =
  # Do we want to see the ignored dates?

  if params.ignore:
    let ignored = readApodIgnore(params.dest)
    if ignored.len == 0:
      echo "No dates ignored."
    else:
      echo fmt"{ignored.len} to dates to ignore."
      if params.verbose:
        for i in ignored:
          echo i
    quit(0)

  # First, check what needs to be downloaded.
  var toDownload = getPicturesToDownload(params.dest)

  # Do we want to actually download?
  # Nope!
  if params.dryRun:
    case toDownload.len
    of 0:
      echo "All pictures are already here!"
    of 1:
      echo "There is only one picture to download."
    else:
      echo "There are ", toDownload.len, " pictures to download."

    if params.verbose:
      for picture in toDownload:
        echo fmt"{picture.date}: picture.title"

  # Yup!
  else:
    case toDownload.len
    of 0:
      echo "All pictures are already here!"
    of 1:
      echo "Downloading one picture..."
    else:
      echo "Downloading ", toDownload.len, " pictures..."

    let pictures = waitFor downloadPictures(params.dest, toDownload)
    for picture in pictures:
      case picture.error:
      of "":
        if params.verbose:
          echo fmt"Downloaded {picture.date} ({picture.title})."
      of "Not an image":
        if params.verbose:
          echo fmt"Skipping {picture.date} ({picture.title}) because it's not a picture."
      else:
        writeLine(stderr, &"Error while retrieving {picture.date} ({picture.title}):")
        writeLine(stderr, "  ", picture.error)


when(isMainModule):
  let params = cli()
  main(params)
