

# buildr

A very simple minded build server, until [r-hub](https://github.com/r-hub) is working.  Don't use this for anything serious and use r-hub when it comes out because it's going to be way better.

## Using the client

You need the hostname of the build server, and the port if it is running on a non-default port.  The simplest thing is to run:


```r
res <- buildr::build_binaries("seagull_1.0.0.tar.gz", "localhost", port=9999L)
```

```
## This is buildr
```

```
## Waiting for seagull_1.0.0.tar.gz to build:
```

```
## .......
```

```
## seagull_1.0.0_R_x86_64-pc-linux-gnu.tar.gz
```

```r
res
```

```
## [1] "/tmp/RtmpeWfCkN/file501d779f5e4f/seagull_1.0.0_R_x86_64-pc-linux-gnu.tar.gz"
```

which will submit the package to server and poll until it builds or fails.  By default the created binary file is copied into a temporary directory, but you can control this with the `dest` argument.  If the build fails, the log will be printed along with an id (see below).

The argument to `build` can be a vector of filenames, in which case the packages will be built in order (so you can build a set of dependent packages).

### More details

Create a connection to the buildr server


```r
cl <- buildr::buildr_client("localhost", 9999L)
```

You can test the connection is OK:


```r
cl$ping()
```

```
## [1] "This is buildr"
```

(this will hang, possibly forever, if it fails).



**Submit a package**.  The package must be a path to a `tar.gz` file built with `R CMD build` or `devtools::build` (i.e., a *source* package).  The filename will typically have an embedded version number.


```r
id <- cl$submit("seagull_1.0.0.tar.gz")
id
```

```
## [1] "fdcb0213e7e3e3058268ba926497fb89"
```

The identifier is the md5 fingerprint of your source file, which you can also find with `tools::md5sum`:


```r
tools::md5sum("seagull_1.0.0.tar.gz")
```

```
##               seagull_1.0.0.tar.gz
## "fdcb0213e7e3e3058268ba926497fb89"
```

You can see source packages that the server knows about:


```r
cl$packages()
```

```
## [1] "fdcb0213e7e3e3058268ba926497fb89"
```

To get the actual name of the source files, pass `translate=TRUE`:


```r
cl$packages(translate=TRUE)
```

```
## [1] "seagull_1.0.0.tar.gz"
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
## .......
```

```r
filename
```

```
## [1] "/tmp/RtmpeWfCkN/file501d641e49b9/seagull_1.0.0_R_x86_64-pc-linux-gnu.tar.gz"
```

The return value here is the filename where the binary has been copied to.  You can also get this with:


```r
cl$download(id)
```

```
## [1] "/tmp/RtmpeWfCkN/file501d6626b6e0/seagull_1.0.0_R_x86_64-pc-linux-gnu.tar.gz"
```

(by default, both `wait` and `download` use a temporary directory but this is configurable with the `dest` argument).

The build log can be retrieved:


```r
cl$log(id)
```

```
## Installing dependencies: R6
## Installing into library: /home/rich/Documents/src/buildr/tests/testthat/test_servers/tmp.MCqkwqsPZz/lib
## trying URL 'http://cran.rstudio.com/src/contrib/R6_2.1.2.tar.gz'
## Content type 'application/x-gzip' length 270461 bytes (264 KB)
## ==================================================
## downloaded 264 KB
##
## * installing *source* package ‘R6’ ...
## ** package ‘R6’ successfully unpacked and MD5 sums checked
## ** R
## ** inst
## ** preparing package for lazy loading
## ** help
## *** installing help indices
## ** building package indices
## ** installing vignettes
## ** testing if installed package can be loaded
## * DONE (R6)
##
## The downloaded source packages are in
## 	‘/tmp/RtmpqyPAtd/downloaded_packages’
## Building into library: /home/rich/Documents/src/buildr/tests/testthat/test_servers/tmp.MCqkwqsPZz/lib
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
## installing to /home/rich/Documents/src/buildr/tests/testthat/test_servers/tmp.MCqkwqsPZz/lib/seagull/libs
## ** R
## ** inst
## ** preparing package for lazy loading
## ** help
## *** installing help indices
## ** building package indices
## ** testing if installed package can be loaded
## * creating tarball
## packaged installation of ‘seagull’ as ‘seagull_1.0.0_R_x86_64-pc-linux-gnu.tar.gz’
## * DONE (seagull)
```

The `packages()` method has an argument `binary` that lists binary packages:


```r
cl$packages(binary=TRUE)
```

```
## [1] "fdcb0213e7e3e3058268ba926497fb89"
```

```r
cl$packages(binary=TRUE, translate=TRUE)
```

```
## [1] "seagull_1.0.0_R_x86_64-pc-linux-gnu.tar.gz"
```

There is also an method `installed` that lists packages installed on the server


```r
cl$installed()
```

```
## [1] "R6"      "seagull"
```

If package versions are behind, you can get the server to upgrade everything with


```r
cl$upgrade()
```

```
## [1] TRUE
```

# Server

The file `inst/run.py` file controlls the server.  Running `./inst/run.py` gives options:

```
usage: run.py [-h] [--root ROOT] [--port PORT] [--expose] [--R R]

Run a buildr server.

optional arguments:
  -h, --help   show this help message and exit
  --root ROOT  path for root of server
  --port PORT  port to run server on
  --expose     Exose the server to the world?
  --R R        Path to Rscript (if not on $PATH)
```
