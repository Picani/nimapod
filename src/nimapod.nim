import asyncdispatch, browsers, os, parsecfg, strformat, tables

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

proc openDate(d: Date) =
  let path = fmt"ap{d.year[2..3]}{d.month}{d.day}.html"
  openDefaultBrowser(fmt"https://apod.nasa.gov/apod/{path}")


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# Making the CLI

let doc = fmt"""
{appName}

Download and manage pictures from NASA Astronomy Picture Of the Day (APOD).

The download command download and put the pictures into a hierarchy of folders
sorted by date. By default, it uses the DEMO_KEY api key, which offers a very
limited number of requests.

The ignore command prints out the ignored dates.

The open command opens the given date in the user's default browser.


Usage:
  {appName} download [<destination>] [-n -v] [--apikey=KEY]
  {appName} ignore   [<destination>]
  {appName} open     <date>

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
    open: bool
    date: string


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

  if args["open"]:
    result.open = true
    result.date = $args["<date>"]
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
  # Check for the open command
  if params.open:
    let d = newDate(params.date)
    openDate(d)
    quit()

  # Do we want to see the ignored dates?
  if params.ignore:
    let ignored = readApodIgnore(params.dest)
    if ignored.len == 0:
      echo "No dates ignored."
    else:
      echo fmt"{ignored.len} dates to ignore."
      if params.verbose:
        for i in ignored:
          echo i
    quit(0)

  waitFor download(params.dest, params.apiKey, params.verbose, params.dryRun)


when(isMainModule):
  let params = cli()
  main(params)
