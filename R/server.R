## What's not clear is how the http server and the file monitoring
## server should interact.  I want to poll both but it's not clear
## that should really be done.
##
## One option would be to write something that monitors a directory
## and if a file is found to fire off an HTTP request.  I think that's
## the right move.
##
## The server should also launch a number of workers.  Doing this via
## parallel is probably ideal because then we'll always shut them down
## on exit.  The issue is logging, and the fact that parallel is
## terrible.
buildr_server <- function(path, n_workers,
                          host="0.0.0.0", port=8765, loop=TRUE) {
  ## TODO: Advertise the URL in the directory.
  app <- buildr_server_app(path, n_workers)
  base_url <- sprintf("http://%s:%d", host, port)
  report_url <- sub("0.0.0.0", "127.0.0.1", base_url, fixed=TRUE)
  buildr_log("Starting server on %s", report_url)
  if (loop) {
    tryCatch(httpuv::runServer(host, port, app),
             interrupt=function(e) {
               message("Catching interrupt and quitting")
               gc()
             })
  } else {
    httpuv::startServer(host, port, app)
  }
}

## Options here:
##   GET  packages/{source,binary} -> list of packages in source/binary form
##   GET  status/<hash> -> status, by hash
##   GET  log/<hash> -> log of build, by hash
##   GET  binary/<hash> -> get binary by source hash
##   POST submit/filename -> submit package, returning some info
##   GET  queue_status -> queue information
buildr_server_app <- function(path, n_workers) {
  obj <- buildr$new(path, n_workers)

  list(
    call=function(req) {
      dat <- parse_req(req)
      buildr_log("[httpd] %s %s/%s", dat$verb, dat$endpoint, dat$path)

      execute <- switch(
        dat$endpoint,
        packages=endpoint_packages,
        status=endpoint_status,
        log=endpoint_log,
        binary_filename=endpoint_binary_filename,
        binary=endpoint_binary,
        submit=endpoint_submit,
        queue_status=endpoint_queue_status,
        endpoint_unknown)
      ret <- execute(obj, dat)
      buildr_log("[httpd] \t--> %d", ret$status)
      ret
    })
}

parse_req <- function(req) {
  x <- req$PATH_INFO
  verb <- req$REQUEST_METHOD
  re <- "^/([^/]+)/?(.*)"
  endpoint <- sub(re, "\\1", x)
  path <- sub(re, "\\2", x)
  path_split <- strsplit(path, "/", fixed=TRUE)[[1]]

  ret <- list(verb=verb, endpoint=endpoint,
              path=path, path_split=path_split, req=req)
  if (!is.null(req$HTTP_ACCEPT)) {
    ret$accept <- req$HTTP_ACCEPT
  }
  if (!is.null(req$HTTP_CONTENT_TYPE)) {
    ret$content_type <- req$HTTP_CONTENT_TYPE
  }
  if (verb == "POST") {
    con <- req[["rook.input"]]
    if (!is.null(con)) {
      ret$data <- con$read()
    }
  }
  ret
}

endpoint_packages <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1) {
    server_response(if (path == "binary") obj$binary() else obj$source())
  } else {
    server_error()
  }
}

endpoint_binary <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1) {
    filename <- obj$binary_filename(path)
    server_response(readBin(filename, raw(), file.size(filename)))
  } else {
    server_error()
  }
}

endpoint_status <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1L) {
    server_response(obj$status(path))
  } else {
    server_error()
  }
}

endpoint_log <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1L) {
    log <- obj$log(path)
    if (is.null(log)) {
      server_error("Not found", 404L)
    } else {
      server_response(log, type="text/plain")
    }
  } else {
    server_error()
  }
}

endpoint_binary_filename <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1L) {
    binary_filename <- obj$binary_filename(path)
    if (is.null(binary_filename)) {
      server_error("Not found", 404L)
    } else {
      server_response(basename(binary_filename), type="text/plain")
    }
  } else {
    server_error()
  }
}

endpoint_submit <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "POST" && length(path) == 1L) {
    tmp <- tempfile()
    writeBin(dat$data, tmp)
    server_response(obj$submit(tmp))
  } else {
    server_error()
  }
}

endpoint_queue_status <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 0L) {
    ret <- obj$queue_status()
    server_response(ret)
  } else {
    server_error()
  }
}

endpoint_unknown <- function(obj, dat) {
  server_error("Unknown endpoint", 404L)
}

server_response <- function(body, status=200L, type="application/json") {
  if (is.raw(body)) {
    type <- "application/octet-stream"
  } else if (type == "application/json" && !inherits(body, "json")) {
    body <- jsonlite::toJSON(body, auto_unbox=TRUE)
  }
  list(status=status, headers=list("Content-Type"=type), body=body)
}

server_error <- function(message="Invalid request", status=400L,
                         type="text/plain") {
  server_response(message, status, type)
}
