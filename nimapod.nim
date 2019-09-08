import
  asyncdispatch, hashes, httpclient, json, os, parseopt, parsexml, sequtils,
  sets, streams, strformat, strutils, tables

#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# Our constants
const appName = "nimapod"
const appVersion = "1.0.0"
const apodIndex = "https://apod.nasa.gov/apod/archivepix.html"
const apodApi = "https://api.nasa.gov/planetary/apod"


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# Our datatypes
type
  Date = object
    ## A date
    year: string
    month: string
    day: string

  Picture = object
    ## A picture metadata
    date: Date
    title: string
    explanation: string
    url: string
    error: string  # Empty if no error

  Params = object
    ## The CLI parameters
    dest: string
    dryRun: bool
    verbose: bool
    ignore: bool

func hash(d: Date): Hash =
  ## Hash.hash implementation for Date
  var h: Hash = 0
  h = h !& hash(d.year) !& hash(d.month) !& hash(d.day)
  result = !$h

func `$`(d: Date): string =
  ## system.$ implementation for Date
  return fmt"{d.year}/{d.month}/{d.day}"


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# The .apodignore file

proc readApodIgnore(root: string): seq[Date] =
  ## Read a .apodignore file inside ``root`` directory, and return the Date
  ## it contains. If the file doesn't exist, create it, and return an empty
  ## sequence.
  let path = fmt"{root}/.apodignore"
  var file: File
  defer: file.close()
  if not existsFile(path):
    file = open(path, fmWrite)
  else:
    file = open(path)

    var content = file.readAll().splitLines()
    .map(proc(line: string): string = line.strip)
    .filter(proc(s: string): bool = s.len > 0)

    if content.len > 0:
      result = content
      .map(proc(line: string): seq[string] = line.strip().split('/'))
      .map(proc(s: seq[string]): Date = Date(year: s[0], month: s[1], day: s[2]))


proc appendApodIgnore(root: string, pictures: seq[Picture]) =
  ## Append the dates of these ``pictures`` to the ``root/.apodignore`` file.
  let path = fmt"{root}/.apodignore"
  var file = open(path, fmAppend)
  defer: file.close()

  for p in pictures:
    file.writeLine(fmt"{p.date.year}/{p.date.month}/{p.date.day}")


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# Procedures that works on the index

proc getPicturesDateInDir(dir: string): HashSet[Date] =
  ## Walk through ``dir``, extracting the date from the path of each file
  ## (which is ``dir/year/month/day - title.(png|jpg|gif)``). Add to the
  ## results the date in ``dir/.apodignore``.
  var alreadyPresent: HashSet[Date]
  for filepath in walkDirRec(dir, relative = true):
    try:
      let date = filepath.split(" - ")[0].split('/')
      let d = Date(year: date[0], month: date[1], day: date[2])
      alreadyPresent.incl(d)
    # If we cannot split the name correctly, it doesn't interest us.
    except IndexError:
      continue

  let ignored = toHashSet(readApodIgnore(dir))
  return alreadyPresent + ignored


func href2Date(href: string): Date =
  ## Convert an APOD href of the form ``ap190707.html`` to a Date object.
  Date(year: if href[2] == '9':
    @["19", href[2..3]].join
  else:
    @["20", href[2..3]].join,
    month: href[4..5],
    day: href[6..7])


proc extractIndex(content: string): Table[Date, Picture] =
  ## Extract the date and title of each pictures from the content of the
  ## index page.
  var
    strm = newStringStream(content)
    x: XmlParser

  open(x, strm, "index")
  # The list of pictures is inside a huge <b> tag. The whole page contains
  # 4 <b> tags, the one we want being the first.
  while true:
    x.next()
    if x.kind == xmlElementStart and x.elementName == "b":
      break

  while true:
    x.next
    case x.kind
    of xmlElementOpen:
      if x.elementName == "a":
        x.next # the href
        let date = href2Date(x.attrValue)
        x.next # the closing ">"
        x.next # the title

        var title = ""
        while x.kind == xmlCharData:
          title.add(x.charData)
          x.next()

        result[date] = Picture(title: title, date: date)

    of xmlElementStart:
      if x.elementName == "b":
        break
    else:
      discard

  x.close()


proc getIndex(): Table[Date, Picture] =
  ## Download the index page and return the index of pictures.
  var client = newHttpClient()
  let indexContent = client.getContent(apodIndex)
  extractIndex(indexContent)


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# Downloading procedures

proc getPictureUrl(pict: Picture): Future[Picture] {.async.} =
  ## Asynchronously fetch the URL for that ``picture``. Return a new picture
  ## with either an URL and an empty error, or an error and an empty URL.
  result = Picture(date: pict.date, title: pict.title)

  var client = newAsyncHttpClient()
  let query = fmt"{apodApi}?date={pict.date.year}-{pict.date.month}-{pict.date.day}&api_key=DEMO_KEY&hd=true"

  let future = client.get(query)
  yield future

  if future.failed:
    # result.error = "Le futur a échoué."
    result.error = future.error.msg
  else:
    let resp = future.read()
    let body = resp.body.read()
    let content = parseJson(body)

    case resp.code
    of Http200:
      if content["media_type"].getStr() != "image":
        result.error = "Not an image"
      elif content.hasKey("hdurl"):
        result.url = content["hdurl"].getStr()
      else:
        result.url = content["url"].getStr()
    of Http403:
      result.error = content["error"]["message"].getStr()
    of Http429:
      result.error = content["error"]["message"].getStr()
    else:
      result.error = body


proc fetchPicture(root: string, pict: Picture): Future[Picture] {.async.} =
  ## Actually fetch the picture and save it into ``root/YYYY/MM/DD - title``.
  ## If something's wrong, put a description into the returned Picture.error
  ## field, else left it empty.
  result = Picture(date: pict.date, title: pict.title)

  var client = newAsyncHttpClient()
  let d = pict.date
  let ext = splitFile(pict.url)[2]
  let filename = fmt"{root}/{d.year}/{d.month}/{d.day} - {pict.title}{ext}"

  let future = client.downloadFile(pict.url, filename)
  yield future

  if future.failed:
    result.error = future.error.msg


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# Making the CLI

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
