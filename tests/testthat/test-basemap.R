boundaries_path <- file.path(root, "data", "raw", "paris_arrondissements.geojson")
water_path <- file.path(root, "data", "raw", "paris_waterways.geojson")
basemap <- build_basemap(velib, boundaries_path, water_path)

test_that("simplification keeps the endpoints and stays within tolerance", {
  t <- seq(0, 2 * pi, length.out = 400)
  wave <- cbind(t, sin(t))
  slim <- simplify_line(wave, 0.01)
  expect_lt(nrow(slim), 60)
  expect_equal(slim[c(1, nrow(slim)), ], wave[c(1, 400), ])
  # The tolerance is perpendicular distance; measured vertically on a slope of
  # up to one, that is at most the tolerance times the square root of two.
  expect_lt(max(abs(stats::approx(slim[, 1], slim[, 2], t)$y - wave[, 2])), 0.01 * sqrt(2))
  straight <- cbind(1:10, 1:10)
  expect_equal(nrow(simplify_line(straight, 0.001)), 2)
  expect_equal(simplify_line(straight[1:2, ], 1), straight[1:2, ])
})

test_that("rings stay closed and keep their area", {
  t <- seq(0, 2 * pi, length.out = 500)
  circle <- cbind(cos(t), sin(t))
  slim <- simplify_ring(circle, 0.01)
  expect_equal(slim[1, ], slim[nrow(slim), ], tolerance = 1e-12)
  expect_lt(nrow(slim), 60)
  expect_equal(ring_area(slim), pi, tolerance = 0.02)
  expect_equal(ring_area(cbind(c(0, 2, 2, 0, 0), c(0, 0, 3, 3, 0))), 6)
})

test_that("the base map is Paris, in the stations' coordinates", {
  expect_length(basemap$boundaries, 20)
  # The twenty arrondissements cover about 105 square kilometres.
  expect_equal(sum(vapply(basemap$boundaries, ring_area, numeric(1))), 105.4, tolerance = 0.01)
  expect_lt(sum(vapply(basemap$boundaries, nrow, numeric(1))), 1000)
  expect_gt(length(basemap$water), 10)
  all_xy <- do.call(rbind, basemap$boundaries)
  expect_true(all(abs(all_xy[, 1]) < 12 & abs(all_xy[, 2]) < 8))
  # Most stations are inside the city, so the two layers must overlap.
  s <- velib$stations
  inside <- s$x > min(all_xy[, 1]) & s$x < max(all_xy[, 1]) & s$y > min(all_xy[, 2]) & s$y < max(all_xy[, 2])
  expect_gt(mean(inside), 0.9)
})

test_that("the base map exports as rings of matching x and y", {
  path <- export_basemap(basemap, withr::local_tempfile(fileext = ".json"))
  j <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  expect_match(j$source, "Open Database Licence")
  expect_length(j$boundaries, 20)
  for (ring in c(j$boundaries, j$water)) expect_equal(length(ring$x), length(ring$y))
})
