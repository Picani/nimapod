## The datatypes, constants and stuff related to the `.apodignore` file.

import hashes, os, sequtils, strformat, strutils


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# The constants

const appName* = "nimapod"
const appVersion* = "2.0.0"
const apodIndex* = "https://apod.nasa.gov/apod/archivepix.html"
const apodApi* = "https://api.nasa.gov/planetary/apod"


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# The datatypes

type
  Date* = object
    ## A date
    year*: string
    month*: string
    day*: string

  Picture* = object
    ## A picture metadata
    date*: Date
    title*: string
    explanation*: string
    url*: string
    error*: string  # Empty if no error

func hash*(d: Date): Hash =
  ## Hash.hash implementation for Date
  var h: Hash = 0
  h = h !& hash(d.year) !& hash(d.month) !& hash(d.day)
  result = !$h

func `$`*(d: Date): string =
  ## system.$ implementation for Date
  return fmt"{d.year}/{d.month}/{d.day}"


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# The .apodignore file

proc readApodIgnore*(root: string): seq[Date] =
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


proc appendApodIgnore*(root: string, pictures: seq[Picture]) =
  ## Append the dates of these ``pictures`` to the ``root/.apodignore`` file.
  let path = fmt"{root}/.apodignore"
  var file = open(path, fmAppend)
  defer: file.close()

  for p in pictures:
    file.writeLine(fmt"{p.date.year}/{p.date.month}/{p.date.day}")
