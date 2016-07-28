## This is the main entry point that the script will use.
build_binary <- function(filename, dest) {
  install_deps(filename)
  do_build_binary(filename, dest)
}

install_deps <- function(filename, suggests=FALSE, ..., lib=.libPaths()[[1]]) {
  r <- getOption("repos")
  r[["CRAN"]] <- "https://cran.rstudio.com"
  oo <- options(repos=r)
  on.exit(options(oo))
  deps <- get_deps(extract_DESCRIPTION(filename), suggests)
  needed <- setdiff(deps, .packages(TRUE, union(lib, .libPaths())))
  if (length(needed) > 0L) {
    message("Installing dependencies: ", paste(needed, collapse=", "))
    install.packages(deps, ..., lib=lib)
  }
}

do_build_binary <- function(filename, dest) {
  dir.create(dest, FALSE, TRUE)
  if (!file.info(dest)[["isdir"]]) {
    stop("dest must be a directory")
  }

  lib <- tempfile()
  dir.create(lib)
  workdir <- tempfile()
  dir.create(workdir)
  owd <- setwd(workdir)

  on.exit({
    setwd(owd)
    unlink(lib, recursive=TRUE)
    unlink(workdir, recursive=TRUE)
  })

  args <- c("CMD", "INSTALL", "--build", normalizePath(filename))
  env <- c(R_LIBS = paste(c(lib, .libPaths()), collapse=.Platform$path.sep),
            CYGWIN = "nodosfilewarning")
  env <- sprintf("%s=%s", names(env), unname(env))
  ok <- system2(file.path(R.home(), "bin", "R"), args, env=env)
  if (ok != 0L) {
    stop(sprintf("Command failed (code: %d)", ok))
  }

  files <- dir()
  stopifnot(length(files) == 1L)
  file.copy(files, dest)
  if (dest == ".") files else file.path(dest, files)
}

extract_DESCRIPTION <- function(filename) {
  files <- untar(filename, list=TRUE)
  desc <- grep("^[^/]+/DESCRIPTION$", files, value=TRUE)
  if (length(desc) != 1L) {
    stop("Invalid package file")
  }
  tmp <- tempfile()
  ok <- untar(filename, desc, exdir=tmp)
  if (!file.exists(file.path(tmp, desc))) {
    stop("Error extracting DESCRIPTION")
  }
  on.exit(unlink(tmp, recursive=TRUE))
  read.dcf(file.path(tmp, desc))
}

## Based on drat builder:
get_deps <- function(desc, suggests=FALSE) {
  cols <- c("Depends", "Imports", if (suggests) "Suggests")
  jj <- intersect(cols, colnames(desc))
  val <- unlist(strsplit(desc[, jj], ","), use.names=FALSE)
  val <- gsub("\\s.*", "", trimws(val))
  val[val != "R"]
}
