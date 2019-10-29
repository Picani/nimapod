## The datatypes, constants and stuff related to the `.apodignore` file.

import hashes, os, sequtils, strformat, strutils


#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
# The constants

const appName* = "nimapod"
const appVersion* = "2.0.2"
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

func newDate*(s: string): Date =
  ## Create a Date from the string ``s``. It is expected to be of the form
  ## YYYY/MM/DD or YYYY_MM_DD or YYYY-MM-DD or YYYYMMDD, with YYYY the year in either 4
  ## digits or 2 digits (95 to 99 being 1995 to 1999, the rest being after
  ## 1999), MM being the month (from 01 to 12) and DD the day (from 01 to 31).
  ##
  ## No check is done on the created Date (*i.e.* it's possible to create a
  ## February 31). It's up to the user to create meaningful date.
  var year, month, day: string
  case s.len
  of 10:  # YYYY/MM/DD or YYYY_MM_DD or YYYY-MM-DD
    year = s[..3]
    month = s[5..6]
    day = s[8..9]
  of 8:
    if s[2].isDigit():  # YYYYMMDD
      year = s[..3]
      month = s[4..5]
      day = s[6..7]
    else:  # YY/MM/DD or YY_MM_DD or YY-MM-DD
      year = s[..1]
      month = s[3..4]
      day = s[6..7]
  of 6:  # YYMMDD
    year = s[..1]
    month = s[2..3]
    day = s[4..5]
  else:
    raise newException(ValueError, fmt"unable to read date {s}")

  if year.len == 2:
    if year[0] == '9':
      year = "19" & year
    else:
      year = "20" & year
  Date(year: year, month: month, day: day)


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
