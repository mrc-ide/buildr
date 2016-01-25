context("buildr")

test_that("buildr", {
  skip_on_travis()
  skip_if_no_buildr()
  Sys.setenv("R_TESTS" = "")
  filename <-
    download_file("https://github.com/richfitz/kitten/archive/master.tar.gz",
                  file.path(tempdir(), "kitten.tar.gz"), TRUE)

  cl <- buildr_client("localhost")

  expect_equal(cl$packages(), character(0))
  expect_equal(cl$packages(TRUE), character(0))

  res <- cl$submit(filename)
  res2 <- cl$submit(filename)

  expect_true(res$build)
  expect_equal(res$hash_source, hash_file(normalizePath(filename)))
  expect_is(res$task_id, "character")

  expect_false(res2$build)
  expect_equal(res2$reason, "already_queued")

  tmp <- cl$packages()
  expect_is(tmp, "data.frame")
  expect_equal(tmp$hash_source, res$hash_source)
  expect_equal(tmp$filename_source, basename(filename))

  ign <- cl$wait(res$hash_source, poll=0.1, timeout=3)

  status <- cl$status(res$hash_source)
  expect_true(status$success)
  expect_equal(status[c("hash", "task_id")],
               res[c("hash", "task_id")])

  expect_is(status$hash_binary, "character")
  expect_is(status$filename_binary, "character")

  filename_binary <- cl$filename_binary(res$hash_source)
  expect_equal(filename_binary, status$filename_binary)

  qst <- cl$queue_status()
  expect_is(qst, "data.frame")
  expect_equal(nrow(qst), 1L)

  expect_equal(cl$packages(), tmp)
  tmp2 <- cl$packages(TRUE)
  expect_equal(tmp2$filename_binary, status$filename_binary)

  log <- cl$log(res$hash_source)
  expect_is(log, "build_log")
  expect_equal(length(log), 1L)
  expect_match(log, "installing *source* package", fixed=TRUE)

  f <- cl$binary(res$hash_source)
  expect_true(file.exists(f))

  ## temporary lib:
  tmp <- tempfile()
  dir.create(tmp)
  install.packages(f, repos=NULL, lib=tmp)
  expect_equal(.packages(TRUE, tmp), "kitten")

  res2 <- cl$submit(filename)
  expect_false(res2$build)
  expect_equal(res2$reason, "up_to_date")
})
