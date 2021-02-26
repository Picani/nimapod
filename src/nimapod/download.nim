## Contains procedures related to index parsing and pictures downloading.

import asyncdispatch, httpclient, os, json, parsexml, sets, streams,
       strformat, strutils, tables

import common

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
  # 4 <b> tags, the one we want being the second.
  var second = false
  while true:
    x.next()
    if x.kind == xmlElementStart and x.elementName == "b":
      if second:
        break
      second = true

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


proc getPicturesToDownload*(root: string): seq[Picture] =
  ## Download the index, compare it against the pictures in ``root``,
  ## exclude the pictures to ignore and return the remaining pictures.
  let
    alreadyThere = getPicturesDateInDir(root)
    index = getIndex()

  var dates: HashSet[Date]
  for date in index.keys():
      dates.incl(date)

  let datesToDownload = dates - alreadyThere
  for date in datesToDownload:
      result.add(index[date])


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# Downloading procedures

proc getPictureUrl(apikey: string, pict: Picture): Future[Picture] {.async.} =
  ## Asynchronously fetch the URL for that ``picture``. Return a new picture
  ## with either an URL and an empty error, or an error and an empty URL.
  result = Picture(date: pict.date, title: pict.title)

  var client = newAsyncHttpClient()
  let query = fmt"{apodApi}?date={pict.date.year}-{pict.date.month}-{pict.date.day}&api_key={apikey}&hd=true"

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
  let title = pict.title.replace("/", " ")
  let filename = fmt"{root}/{d.year}/{d.month}/{d.day} - {title}{ext}"

  let future = client.downloadFile(pict.url, filename)
  yield future

  if future.failed:
    result.error = future.error.msg


proc downloadPictures(root, apikey: string, pictures: seq[Picture]): Future[seq[Picture]] {.async.} =
  ## Download all ``pictures`` and put them in ``root`` accordingly to their
  ## date, while updating the ``.apodignore`` file if needed.
  ## Return a new seq of pictures with the ``error`` field set if any.

  # First, we create all directories
  createDir(root)
  for picture in pictures:
    var date = picture.date
    createDir(fmt"{root}/{date.year}/{date.month}")

  # Let's fetch the URL and check for errors or things we don't want.
  var futuresUrls = newSeq[Future[Picture]]()
  for picture in pictures:
    futuresUrls.add(getPictureUrl(apikey, picture))

  let urls = await all(futuresUrls)
  var
    futureDownloads = newSeq[Future[Picture]]()
    toIgnore = newSeq[Picture]()
  for picture in urls:
    case picture.error:
    of "":
      futureDownloads.add(fetchPicture(root, picture))
    of "Not an image":
      toIgnore.add(picture)
      result.add(picture)
    else:
      result.add(picture)

  # We update the .apodignore file
  appendApodIgnore(root, toIgnore)

  # Let's actually download the pictures and check for errors.
  let downloaded = await all(futureDownloads)
  result &= downloaded


proc download*(root, apiKey: string, verbose, dryRun: bool) {.async.} =
  ## Correspond to the **download** command.
  ##
  ## In ``root``, create the needed directories, download the missing
  ## pictures and update the .apodignore file. Write to stdout or stderr
  ## what needs to be, depending upon the value of ``verbose``. Use the
  ## ``apiKey`` to download the picture and the NASA API. If ``dryRun``
  ## is true, only print the (number of) missing pictures.
  # First, check what needs to be downloaded.
  let toDownload = getPicturesToDownload(root)

  # Do we want to actually download?
  # Nope!
  if dryRun:
    case toDownload.len
    of 0:
      echo "All pictures are already here!"
    of 1:
      echo "There is only one picture to download."
    else:
      echo "There are ", toDownload.len, " pictures to download."

    if verbose:
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

    let pictures = await downloadPictures(root, apikey, toDownload)
    for picture in pictures:
      case picture.error:
      of "":
        if verbose:
          echo fmt"Downloaded {picture.date} ({picture.title})."
      of "Not an image":
        if verbose:
          echo fmt"Skipping {picture.date} ({picture.title}) because it's not a picture."
      else:
        writeLine(stderr, &"Error while retrieving {picture.date} ({picture.title}):")
        writeLine(stderr, "  ", picture.error)
