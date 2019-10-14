import asyncdispatch, os, parsecfg, parseopt, sets, strformat, tables

import docopt

import nimapod/[common, download]


proc readConfig(): Config =
  ## Read the config file ``$XDG_CONFIG_HOME/nimapodrc`` and return the
  ## config it contains.
  ## If the file doesn't exist, don't create it and return an empty config.
  var path = joinPath(getConfigDir(), "nimapodrc")
  if existsFile(path):
    result = loadConfig(path)
  else:
    result = newConfig()


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# Making the CLI

let doc = fmt"""
{appName}

Download and manage pictures from NASA Astronomy Picture Of the Day (APOD).

The download command download and put the pictures into a hierarchy of folders
sorted by date. By default, it uses the DEMO_KEY api key, which offers a very
limited number of requests.

The ignore command prints out the ignored dates.

Usage:
  {appName} download [<destination>] [-n -v] [--apikey=KEY]
  {appName} ignore   [<destination>]

  {appName} -h|--help
  {appName} -V|--version

Options:
  -h, --help       Show this help and exit.
  -V, --version    Show version information.
  -v, --verbose    Be verbose.

  -n, --dry-run    Print what would be downloaded and exit.
  --apikey=KEY     Use this API key instead of the default one.
"""

type
  Params = object
    ## The CLI parameters
    dest: string
    dryRun: bool
    verbose: bool
    ignore: bool
    apikey: string


proc cli(): Params =
  var config = readConfig()
  var args = docopt(doc, version = fmt"{appName} v{appVersion}")

  result.dest = config.getSectionValue("", "destination")
  result.apikey = config.getSectionValue("", "apikey")

  if args["<destination>"]:
    result.dest = $args["<destination>"]

  if args["ignore"]:
    result.ignore = true
    return result  # We don't care for the rest

  result.dryRun = args["--dry-run"]
  result.verbose = args["--verbose"]
  if args["--apikey"]:
    result.apikey = $args["--apikey"]
  elif result.apikey == "":
    result.apikey = "DEMO_KEY"


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
  let toDownload = getPicturesToDownload(params.dest)

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
        echo fmt"{picture.date}: {picture.title}"

  # Yup!
  else:
    case toDownload.len
    of 0:
      echo "All pictures are already here!"
    of 1:
      echo "Downloading one picture..."
    else:
      echo "Downloading ", toDownload.len, " pictures..."

    let pictures = waitFor downloadPictures(params.dest, params.apikey, toDownload)
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
