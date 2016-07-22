

# buildr

A very simple minded build server, until [r-hub](https://github.com/r-hub) is working.  Don't use this for anything serious and use r-hub when it comes out because it's going to be way better.

# Using the client

You need the hostname of the build server, and the port if it is running on a non-deafult port


```r
cl <- buildr::buildr_client("localhost", 9999L)
```

Test that the connection is up (I have intermittent connection problems with the server on Windows).


```r
cl$ping()
```

```
## [1] "This is buildr"
```

(this will hang, possibly forever, if it fails).

**Submit a package**.  The package must be a path to a `tar.gz` file built with `R CMD build` or `devtools::build` (i.e., a *source* package).  The filename will typically have an embedded version number.


```r
id <- cl$submit("seagull_0.0.1.tar.gz")
id
```

```
## [1] "7c14fbe062401e9751f64f670c0294ba"
```

The identifier is the md5 fingerprint of your source file

You can see source packages that the server knows about:


```r
cl$packages()
```

```
## [1] "7c14fbe062401e9751f64f670c0294ba"
```

To get the actual name of the source files, pass `translate=TRUE`:


```r
cl$packages(translate=TRUE)
```

```
## [1] "seagull_0.0.1.tar.gz"
```

and request the status of the package you are building:


```r
cl$status(id)
```

```
## [1] "RUNNING"
```

To block until a package has finished building, use `wait`:


```r
filename <- cl$wait(id)
```

```
## .
```

```r
filename
```

```
## [1] "/tmp/RtmpksI1uo/file61e255194762/seagull_0.0.1_R_x86_64-pc-linux-gnu.tar.gz"
```

The return value here is the filename where the binary has been copied to.  You can also get this with:


```r
cl$download(id)
```

```
## [1] "/tmp/RtmpksI1uo/file61e2702fe50/seagull_0.0.1_R_x86_64-pc-linux-gnu.tar.gz"
```

(by default, both `wait` and `download` use a temporary directory but this is configurable with the `dest` argument).

The build log can be retrieved:


```r
cl$log(id)
```

```
## * installing to library ‘/tmp/Rtmp7zPlLP/file61eb7889d552’
## * installing *source* package ‘seagull’ ...
## ** libs
## gcc -std=gnu99 -I/usr/share/R/include -DNDEBUG      -fpic  -Wall -Wextra -Wno-unused-parameter -c fcntl.c -o fcntl.o
## fcntl.c: In function ‘seagull_fcntl_state’:
## fcntl.c:124:7: warning: unused variable ‘errsv’ [-Wunused-variable]
##    int errsv;
##        ^
## fcntl.c:121:44: warning: unused variable ‘locked’ [-Wunused-variable]
##    int fd = *seagull_get_fd(extPtr, 1), ok, locked;
##                                             ^
## gcc -std=gnu99 -shared -L/usr/lib/R/lib -Wl,-Bsymbolic-functions -Wl,-z,relro -o seagull.so fcntl.o -L/usr/lib/R/lib -lR
## installing to /tmp/Rtmp7zPlLP/file61eb7889d552/seagull/libs
## ** R
## ** inst
## ** preparing package for lazy loading
## ** help
## *** installing help indices
## ** building package indices
## ** testing if installed package can be loaded
## * creating tarball
## packaged installation of ‘seagull’ as ‘seagull_0.0.1_R_x86_64-pc-linux-gnu.tar.gz’
## * DONE (seagull)
```

# Server

The file `inst/run.py` file controlls the server.  Running `./inst/run.py` gives options:

```
usage: run.py [-h] [--root ROOT] [--port PORT] [--expose]

Run a buildr server.

optional arguments:
  -h, --help   show this help message and exit
  --root ROOT  path for root of server
  --port PORT  port to run server on
  --expose     Exose the server to the world?
```
