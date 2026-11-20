# Export the stations and the findings as JSON for the web page.
#
# The page assigns stations to clusters and projects them onto the principal
# components in JavaScript. To make "the page computes what R computes"
# testable, the fixtures are computed in R *from the JSON as written* (after
# rounding), and a JavaScript test must reproduce them.

PAGE_KS <- 2:6
PROFILE_SCALE <- 100  # profiles are exported as whole percentages

write_json <- function(x, path, digits = 6) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(x, path, digits = I(digits), auto_unbox = TRUE,
                       null = "null", na = "null", pretty = FALSE)
  path
}

export_stations <- function(dat, summary, pca, kmeans_fits, path) {
  s <- dat$stations
  scores <- pca_scores(pca, dat$profiles, 2)
  fits <- Filter(function(f) f$k %in% PAGE_KS, kmeans_fits)
  write_json(list(
    days = DAYS,
    scale = PROFILE_SCALE,
    name = s$name,
    x = round(s$x, 3), y = round(s$y, 3),
    lon = round(s$lon, 5), lat = round(s$lat, 5),
    bonus = which(s$bonus) - 1L,
    mean = round(summary$mean_fill, 3),
    score = list(round(scores[, 1], 3), round(scores[, 2], 3)),
    profile = unname(round(dat$profiles * PROFILE_SCALE)),
    pca = list(center = round(unname(pca$center), 5),
               rotation = list(round(pca$rotation[, 1], 6), round(pca$rotation[, 2], 6))),
    clusters = stats::setNames(lapply(fits, function(f) {
      described <- describe_clusters(dat, summary, f$cluster)
      list(
        assign = f$cluster - 1L,
        centre = unname(round(f$centres, 4)),
        groups = lapply(described, function(d) {
          list(label = d$label, level = d$level, movement = d$movement, n = d$n,
               mean_fill = round(d$mean_fill, 3), day_night = round(d$day_night, 3),
               bonus_share = round(d$bonus_share, 3))
        })
      )
    }), vapply(fits, function(f) as.character(f$k), character(1)))
  ), path)
}

export_story <- function(dat, summary, pca, components_90, kmeans_fits, validity, benchmark,
                         gap, mixtures, spatial, moran, bonus, path) {
  four <- Filter(function(f) f$k == 4, kmeans_fits)[[1]]
  described <- describe_clusters(dat, summary, four$cluster)
  write_json(list(
    n = nrow(dat$stations),
    pca = list(explained = pca$explained, components_90 = components_90,
               loadings = list(pca$rotation[, 1], pca$rotation[, 2]),
               level_correlation = stats::cor(pca_scores(pca, dat$profiles, 1)[, 1],
                                              summary$mean_fill),
               moran = moran),
    validity = validity,
    benchmark = benchmark,
    gap_chosen = gap$chosen,
    mixture_bic = mixtures$bic,
    spatial = spatial,
    bonus = bonus,
    four = lapply(described, function(d) d[c("cluster", "label", "n", "mean_fill", "day_night",
                                             "bonus_share", "weekday", "weekend")])
  ), path)
}

# --- Fixtures ---------------------------------------------------------------

#' Rebuild what the page knows from the JSON alone.
stations_from_json <- function(path) {
  j <- jsonlite::fromJSON(path, simplifyVector = TRUE, simplifyDataFrame = FALSE)
  j$profile <- j$profile / j$scale
  j
}

json_scores <- function(j, rows) {
  centred <- sweep(j$profile[rows, , drop = FALSE], 2, j$pca$center)
  # fromJSON reads the two loading vectors as the rows of a 2 x 168 matrix.
  unname(centred %*% t(j$pca$rotation))
}

export_fixtures <- function(stations_path, path, n = 60, seed = 2021) {
  j <- stations_from_json(stations_path)
  rows <- sort(withr::with_seed(seed, sample.int(nrow(j$profile), n)))
  scores <- json_scores(j, rows)
  write_json(list(
    cases = lapply(seq_along(rows), function(i) {
      profile <- j$profile[rows[i], , drop = FALSE]
      list(
        station = rows[i] - 1L,
        score = scores[i, ],
        clusters = lapply(j$clusters, function(cl) {
          d <- as.vector(sq_dist(profile, cl$centre))
          list(nearest = which.min(d) - 1L, distance = sqrt(pmax(d, 0)))
        })
      )
    }),
    # Share of stations whose k-means cluster is also their nearest exported
    # centre: rounding for export should move almost nobody.
    agreement = lapply(j$clusters, function(cl) {
      mean(nearest_centre(j$profile, cl$centre) - 1L == cl$assign)
    })
  ), path, digits = 10)
}
