# A base map for the page: arrondissement boundaries and waterways from the
# City of Paris open data portal (ODbL), reduced to a few thousand points in
# the same kilometre coordinates as the stations.

#' Outer rings of every polygon in a GeoJSON file, as lon/lat matrices.
read_rings <- function(path) {
  geo <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  rings <- list()
  for (feature in geo$features) {
    g <- feature$geometry
    if (is.null(g)) next
    polygons <- switch(g$type, Polygon = list(g$coordinates), MultiPolygon = g$coordinates,
                       stop("Unsupported geometry: ", g$type))
    for (polygon in polygons) {
      outer <- polygon[[1]]
      rings[[length(rings) + 1]] <- cbind(
        lon = vapply(outer, function(p) p[[1]], numeric(1)),
        lat = vapply(outer, function(p) p[[2]], numeric(1))
      )
    }
  }
  rings
}

#' Douglas-Peucker simplification of an open line (two-column matrix).
#' Keeps the points needed to stay within `tolerance` of the original.
simplify_line <- function(xy, tolerance) {
  n <- nrow(xy)
  if (n <= 2) return(xy)
  keep <- rep(FALSE, n)
  keep[c(1, n)] <- TRUE
  stack <- list(c(1L, n))
  while (length(stack)) {
    span <- stack[[length(stack)]]
    stack[[length(stack)]] <- NULL
    a <- span[1]
    b <- span[2]
    if (b - a < 2) next
    inner <- (a + 1):(b - 1)
    d <- xy[b, ] - xy[a, ]
    len <- sqrt(sum(d^2))
    rel <- sweep(xy[inner, , drop = FALSE], 2, xy[a, ])
    dist <- if (len == 0) sqrt(rowSums(rel^2)) else abs(rel[, 1] * d[2] - rel[, 2] * d[1]) / len
    if (max(dist) > tolerance) {
      split <- inner[which.max(dist)]
      keep[split] <- TRUE
      stack[[length(stack) + 1]] <- c(a, split)
      stack[[length(stack) + 1]] <- c(split, b)
    }
  }
  xy[keep, , drop = FALSE]
}

#' Simplify a closed ring by splitting it at its two most distant-looking
#' points, so the result stays closed and never collapses to a line.
simplify_ring <- function(xy, tolerance) {
  n <- nrow(xy)
  if (n < 5) return(xy)
  far <- which.max(rowSums(sweep(xy, 2, xy[1, ])^2))
  first <- simplify_line(xy[1:far, , drop = FALSE], tolerance)
  second <- simplify_line(xy[far:n, , drop = FALSE], tolerance)
  rbind(first, second[-1, , drop = FALSE])
}

ring_area <- function(xy) {
  n <- nrow(xy)
  abs(sum(xy[-n, 1] * xy[-1, 2] - xy[-1, 1] * xy[-n, 2])) / 2
}

#' Project rings to the stations' kilometre grid and simplify them.
#' tolerance and min_area are in kilometres and square kilometres.
prepare_rings <- function(rings, origin, tolerance, min_area = 0) {
  out <- lapply(rings, function(ring) {
    xy <- as.matrix(project_km(ring[, "lon"], ring[, "lat"], origin = origin))
    if (ring_area(xy) < min_area) return(NULL)
    simplify_ring(xy, tolerance)
  })
  Filter(function(r) !is.null(r) && nrow(r) >= 4, out)
}

station_origin <- function(stations) c(mean(range(stations$lon)), mean(range(stations$lat)))

build_basemap <- function(dat, boundaries_path, water_path) {
  origin <- station_origin(dat$stations)
  list(
    boundaries = prepare_rings(read_rings(boundaries_path), origin, tolerance = 0.015),
    water = prepare_rings(read_rings(water_path), origin, tolerance = 0.008, min_area = 0.002)
  )
}

export_basemap <- function(basemap, path) {
  flat <- function(rings) lapply(rings, function(r) list(x = round(r[, 1], 3), y = round(r[, 2], 3)))
  write_json(list(
    source = "Ville de Paris open data (opendata.paris.fr), Open Database Licence",
    boundaries = flat(basemap$boundaries),
    water = flat(basemap$water)
  ), path)
}
