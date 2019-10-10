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

proc main(params: Params) {.async.} =
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
  let alreadyDownloaded = getPicturesDateInDir(params.dest)

  let index = getIndex()
  var allDates: HashSet[Date]
  for date in index.keys():
    allDates.incl(date)

  let toDownload = allDates - alreadyDownloaded

  # Do we want to actually download?
  # Nope!
  if params.dryRun:
    case toDownload.card
    of 0:
      echo "All pictures are already here!"
    of 1:
      echo "There is only one picture to download."
    else:
      echo "There are ", toDownload.card, " pictures to download."

    if params.verbose:
      for date in toDownload:
        echo date.year, "/", date.month, "/", date.day, ": ", index[date].title

  # Yup!
  else:
    case toDownload.card
    of 0:
      echo "All pictures are already here!"
    of 1:
      echo "Downloading one picture..."
    else:
      echo "Downloading ", toDownload.card, " pictures..."

    # First, we create all directories
    createDir(params.dest)
    for date in toDownload:
      createDir(fmt"{params.dest}/{date.year}/{date.month}")

    # Let's get back the pictures.
    var pictures = newSeq[Picture]()
    for date in toDownload:
      pictures.add(index[date])

    # Let's fetch the URL and check for errors or things we don't want.
    var futuresUrls = newSeq[Future[Picture]]()
    for picture in pictures:
      futuresUrls.add(getPictureUrl(picture))

    let picturesUrls = await all(futuresUrls)
    var futuresDownloads = newSeq[Future[Picture]]()
    var toIgnore = newSeq[Picture]()
    for pict in picturesUrls:
      case pict.error
      of "":
        futuresDownloads.add(fetchPicture(params.dest, pict))
      of "Not an image":
        toIgnore.add(pict)
        if params.verbose:
          echo fmt"Skipping {pict.date} ({pict.title}) because it's not a picture."
      else:
        writeLine(stderr, &"Error while retrieving {pict.date} ({pict.title}):")
        writeLine(stderr, "  ", pict.error)

    # We update the .apodignore file
    appendApodIgnore(params.dest, toIgnore)

    # Let's actually download the pictures and check for errors.
    let picturesDownloads = await all(futuresDownloads)
    for pict in picturesDownloads:
      if pict.error == "":
        if params.verbose:
          echo fmt"Downloaded {pict.date} ({pict.title})."
      else:
        writeLine(stderr, &"Error while retrieving {pict.date} ({pict.title}):")
        writeLine(stderr, "  ", pict.error)


when(isMainModule):
  let params = cli()
  waitFor main(params)
