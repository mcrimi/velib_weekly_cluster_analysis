dir <- withr::local_tempdir(.local_envir = testthat::teardown_env())
summary <- station_summary(velib)
pca <- fit_pca(X)
fits <- lapply(2:4, function(k) fit_kmeans(X, k))
stations_path <- export_stations(velib, summary, pca, fits, file.path(dir, "stations.json"))
j <- stations_from_json(stations_path)

test_that("the station export is complete and zero-indexed", {
  expect_equal(dim(j$profile), c(1189, 168))
  expect_equal(length(j$name), 1189)
  expect_setequal(j$bonus + 1, which(velib$stations$bonus))
  expect_equal(names(j$clusters), c("2", "3", "4"))
  expect_equal(range(j$clusters[["4"]]$assign), c(0, 3))
  expect_equal(dim(j$clusters[["4"]]$centre), c(4, 168))
  expect_equal(sum(vapply(j$clusters[["4"]]$groups, function(g) g$n, numeric(1))), 1189)
})

test_that("rounding for export loses almost nothing", {
  expect_lt(max(abs(j$profile - X)), 0.0051)
  expect_equal(json_scores(j, 1:50), unname(pca_scores(pca, X[1:50, ], 2)),
               tolerance = 0.01)
  for (k in names(j$clusters)) {
    cl <- j$clusters[[k]]
    expect_gt(mean(nearest_centre(j$profile, cl$centre) - 1L == cl$assign), 0.995)
  }
})

test_that("fixtures are computed from the JSON and cover every resolution", {
  path <- export_fixtures(stations_path, file.path(dir, "fixtures.json"), n = 20)
  f <- jsonlite::fromJSON(path, simplifyDataFrame = FALSE)
  expect_length(f$cases, 20)
  case <- f$cases[[1]]
  expect_length(case$score, 2)
  expect_equal(names(case$clusters), c("2", "3", "4"))
  expect_equal(case$clusters[["4"]]$nearest, which.min(case$clusters[["4"]]$distance) - 1)
  expect_true(all(unlist(f$agreement) > 0.995))
})
