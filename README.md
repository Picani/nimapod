NimApod
=======

NASA's [Astronomy Picture of the Day][1] (APOD) is one the best website on the
whole internet.

NimApod fetches the pictures from there and put them in a hierarchy of folders
as follow:

    root
       └─ year
             └── month
                     └── day - title

Of course, the pictures are fetched only when there are absent of the
hierarchy. NimApod also ignores days where there's something else than a
picture (a video for example) by using a `.apodignore` file at the root of
the hierarchy.


Installation
------------

NimApod is written in the [Nim programming language][2] and uses the
[Nimble][5] package manager. To build it, you'll need to [install Nim][3]
then to run the following commands:

    $ git clone https://github.com/Picani/nimapod.git
    $ cd nimapod
    $ nimble install


Limitations
-----------

By default, NimApod uses the `DEMO_KEY` API key to issue queries to the NASA's
[public API][4], which is limited to 30 queries/1h or 50 queries/1 day. Another
API key can be specified on the command line or in the configuration file.


Usage
-----

    Usage:
      nimapod download [<destination>] [-n -v] [--apikey=KEY]
      nimapod ignore   [<destination>]
      nimapod open     <date>
    
      nimapod -h|--help
      nimapod -V|--version

    Options:
      -h, --help       Show this help and exit.
      -V, --version    Show version information.
      -v, --verbose    Be verbose.
    
      -n, --dry-run    Print what would be downloaded and exit.
      --apikey=KEY     Use this API key instead of the default one.
      

The download command download and put the pictures into a hierarchy of folders
sorted by date. By default, it uses the DEMO_KEY api key, which offers a very
limited number of requests.

The ignore command prints out the ignored dates.

The open command opens the given date in the user's default browser.


The `destination` argument is the root of the hierarchy of folders. The `date`
argument is a date of the form year/month/day or year-month-day, with year
using 4-digits, and month and day using two digits.


Configuration file
------------------

A configuration file can be used to specify once `destination` and/or `apikey`
and not put them on the command line anymore. This file is named `nimapodrc`
and is in the [default config folder][6] (this should be `$HOME/.config`).

The syntax of the file is simple:

    destination = "/home/plop/ApodPictures"  # $HOME doesn't work...
    apikey = "myPersonalKey"


To Do
-----

Here are the ideas I'd like to implement, in no specific order:

* Open a specific picture in the default image viewer
* Keep the explanations (and other information) in a local database
* Allow to search pictures for a term (for example, all pictures with *Saturn*
  in their title and/or explanation)
* Make the `.apodignore` file accepts glob pattern


License
-------

Copyright © 2019 Sylvain PULICANI picani@laposte.net

This work is free. You can redistribute it and/or modify it under the terms
of the Do What The Fuck You Want To Public License, Version 2, as published
by Sam Hocevar. See the COPYING file for more details.



[1]: https://apod.nasa.gov/apod/astropix.html
[2]: https://nim-lang.org
[3]: https://nim-lang.org/install.html
[4]: https://api.nasa.gov/index.html
[5]: github.com/nim-lang/nimble
[6]: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
