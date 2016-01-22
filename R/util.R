dir_by_time <- function(...) {
  files <- dir(...)
  if (length(files) > 1L) {
    files[order(file.info(files, extra_cols=FALSE)$ctime)]
  } else {
    files
  }
}

dir_create <- function(paths, ...) {
  for (p in paths) {
    dir.create(p, ...)
  }
}

hash_file <- function(x) {
  stopifnot(length(x) == 1L)
  tools::md5sum(x)[[1]]
}

vcapply <- function(X, FUN, ...) {
  vapply(X, FUN, character(1), ...)
}

read_text <- function(filename) {
  readChar(filename, file.size(filename))
}
