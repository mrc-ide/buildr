#!/usr/bin/env Rscript
args <- commandArgs(TRUE)
if (length(args) != 2L) {
  stop("Expected 2 args")
}
file <- args[[1L]]
dest <- args[[2L]]
filename <- buildr:::build_binary(file, dest)
