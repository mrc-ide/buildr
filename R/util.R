hash_file <- function(x) {
  stopifnot(length(x) == 1L)
  tools::md5sum(x)[[1]]
}

vcapply <- function(X, FUN, ...) {
  vapply(X, FUN, character(1), ...)
}

`%or%` <- function(a, b) {
  if (is.null(a)) b else a
}

is_dir <- function(path) {
  file.exists(path) && file.info(path, extra_cols = FALSE)$isdir
}
