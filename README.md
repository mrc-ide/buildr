# buildr

A very simple minded build server, until [r-hub](https://github.com/r-hub) is working.  Don't use this for anything serious and use r-hub when it comes out because it's going to be way better.

# Using the client

You need the hostname of the build server.

```r
cl <- buildr::buildr_client("hostname")
```

Test that the connection is up (I have intermittent connection problems with the server on Windows).

```r
cl$ping()
# [1] "This is buildr 0.0.1"
```

(this will hang, possibly forever, if it fails).

**Submit a package**.  The package must be a path to a `tar.gz` file built with `R CMD build` or `devtools::build` (i.e., a *source* package).  The filename will typically have an embedded version number.

```r
obj <- cl$submit("mypackage_0.0.1.tar.gz")
obj
# $hash_source
# [1] "cc75b2a88c773662c56366c0074b2c3d"
#
# $build
# [1] TRUE
#
# $task_id
# [1] "b3fca7cbddfeda961fe3a93a8535054f"
```

The `hash_source` is the fingerprint of your source file, the `build` is a logical indicating if the package will be built and the `task_id` is the task number from the internal queue.

You can see source packages that the server knows about (this returns a data.frame)

```r
cl$packages()
#                        hash_source        filename_source
# 1 cc75b2a88c773662c56366c0074b2c3d mypackage_0.0.1.tar.gz
```

and request the status of the package you are building:

```r
cl$status(obj$hash_source)
# $success
# [1] TRUE
#
# $filename_source
# [1] "cc75b2a88c773662c56366c0074b2c3d"
#
# $filename_binary
# [1] "cascade_0.0.0.9000.zip"
#
# $hash_source
# [1] "cc75b2a88c773662c56366c0074b2c3d"
#
# $hash_binary
# [1] "a062f264fe74d86ec5ab2789204e18bf"
#
# $task_id
# [1] "b3fca7cbddfeda961fe3a93a8535054f"
```

The build log can be retrieved:

```r
cl$log(obj$hash_source)
# Installing dependencies: deSolve
# trying URL 'https://cran.rstudio.com/bin/windows/contrib/3.2/deSolve_1.12.zip'
# Content type 'application/zip' length 2805011 bytes (2.7 MB)
# ==================================================
# downloaded 2.7 MB
# [...]
# ** testing if installed package can be loaded
# *** arch - i386
# *** arch - x64
# * MD5 sums
# packaged installation of 'mypackage' as mypackage_0.0.1.zip
# * DONE (mypackage)
```

And of course the binary can be retrieved:

```r
filename <- cl$binary(obj$hash_source)
file.exists(filename)
# [1] TRUE
```

Alternatively

```r
filename <- cl$wait(obj$hash_source)
```

will poll (by default every second) until a file is created, or fail after a timeout (by default 60s).

Finally, information about the queue (all jobs) can be retrieved:

```r
> cl$queue_status()
#                        hash_source           filename_source
# 1 cc75b2a88c773662c56366c0074b2c3d cascade_0.0.0.9000.tar.gz
#                            task_id   status           submitted
# 1 b3fca7cbddfeda961fe3a93a8535054f COMPLETE 2016-01-28 15:45:49
#               started            finished waiting running     idle
# 1 2016-01-28 15:45:49 2016-01-28 15:46:12  0.1716 22.2616 366.4666
```

# Server

```r
buildr::buildr_server("workdirectory", n_workers)
```

A lot of files will be created under "workdirectory"; source files, a little database, etc, etc.  If n_workers is 0, then instructions on creating workers will be printed.  You need to create one somehow or nothing will happen.  This runs until interrupted.
