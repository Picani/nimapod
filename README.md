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

NimApod is written in the [Nim programming language][2]. To build it, you'll
need to [install Nim][3] then to run the following command:

    $ nim c -d:release -d:ssl nimapod.nim
    
Finally, place the generated `nimapod` executable somewhere on your `PATH`.


Current Limitations
-------------------

For now, NimApod uses the `DEMO_KEY` API key to issue queries to the NASA's
[public API][4], which is limited to 30 queries/1h or 50 queries/1 day.


To Do
-----

Here are the ideas I'd like to implement, in no specific order:

* Open a specific picture/date in the browser
* Open a specific picture in the default image viewer
* Keep the explanations (and other information) in a local database
* Allow to search pictures for a term (for example, all pictures with *Saturn*
  in their title and/or explanation)
* Make the `.apodignore` file accepts glob pattern
* Allow to specify the API key to use


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
