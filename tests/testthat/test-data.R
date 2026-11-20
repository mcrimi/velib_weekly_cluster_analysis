test_that("the week is complete and starts on Monday", {
  expect_equal(dim(X), c(1189, 168))
  expect_equal(colnames(X)[c(1, 24, 25, 168)], c("Mon-00", "Mon-23", "Tue-00", "Sun-23"))
  expect_equal(as.vector(table(velib$time$day)), rep(24, 7))
  expect_equal(sum(velib$time$weekend), 48)
})

test_that("loadings are shares of docks and nothing else is in the matrix", {
  expect_false(anyNA(X))
  expect_true(all(X >= 0 & X <= 1))
  # The 2021 notebook appended each station's mean as a 169th feature.
  expect_false(any(grepl("mean", colnames(X))))
})

test_that("stations keep their identity and place", {
  s <- velib$stations
  expect_equal(nrow(s), 1189)
  expect_false(anyDuplicated(s$code) > 0)
  expect_equal(sum(s$bonus), 127)
  expect_true(all(s$lon > 2.2 & s$lon < 2.5 & s$lat > 48.8 & s$lat < 48.95))
  expect_equal(s$name, trimws(s$name))
})

test_that("the projection gives distances in kilometres", {
  # One degree of latitude is about 111.2 km; of longitude at 48.86 N about 73.2 km.
  p <- project_km(c(2, 3, 2), c(48.86, 48.86, 49.86), origin = c(2, 48.86))
  expect_equal(p$x[2], 73.2, tolerance = 0.005)
  expect_equal(p$y[3], 111.2, tolerance = 0.005)
  expect_lt(diff(range(velib$stations$x)), 25)
})

test_that("station summaries have the signs their names promise", {
  flat <- matrix(0.5, 1, 168)
  day <- flat
  day[, velib$time$hour %in% 10:16 & !velib$time$weekend] <- 0.9
  s <- station_summary(list(profiles = rbind(flat, day), time = velib$time,
                            stations = data.frame(id = 1:2)))
  expect_equal(s$day_night[1], 0)
  expect_equal(s$day_night[2], 0.4)
  expect_equal(s$mean_fill[1], 0.5)
})
