# Loading and cleaning the Vélib station data.

DAYS <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
DAY_CODES <- c(Lun = "Mon", Mar = "Tue", Mer = "Wed", Jeu = "Thu", Ven = "Fri",
               Sam = "Sat", Dim = "Sun")
HOURS_PER_WEEK <- 168L

load_raw <- function(path) {
  env <- new.env()
  load(path, envir = env)
  stopifnot(exists("velib", envir = env))
  get("velib", envir = env)
}

#' Turn the raw list into a station table and a 168-column loading matrix.
#'
#' The recording starts on a Sunday at 11:00, so the first 13 columns are an
#' incomplete day. They are dropped, leaving Monday 00:00 to Sunday 23:00.
#' Nothing derived from the profiles (such as a station's mean) is added to
#' the matrix: it holds the hourly loadings and nothing else.
clean_velib <- function(raw) {
  profiles <- as.matrix(raw$data)
  stopifnot(nrow(profiles) == length(raw$names), ncol(profiles) == length(raw$dates),
            !anyNA(profiles), all(profiles >= 0), all(profiles <= 1))

  first <- match("Lun-00", raw$dates)
  keep <- first:ncol(profiles)
  stopifnot(length(keep) == HOURS_PER_WEEK)
  labels <- raw$dates[keep]
  day <- unname(DAY_CODES[sub("-.*", "", labels)])
  hour <- as.integer(sub(".*-", "", labels))
  stopifnot(identical(day, rep(DAYS, each = 24)), identical(hour, rep(0:23, 7)))

  profiles <- profiles[, keep, drop = FALSE]
  dimnames(profiles) <- list(NULL, sprintf("%s-%02d", day, hour))

  stations <- data.frame(
    id = seq_len(nrow(profiles)),
    code = rownames(raw$data),
    name = trimws(raw$names),
    lon = raw$position$longitude,
    lat = raw$position$latitude,
    # "Bonus" (V+) stations: the operator gave extra free minutes for returning
    # a bike there, because they are uphill and tend to run empty.
    bonus = raw$bonus == 1,
    stringsAsFactors = FALSE
  )
  stopifnot(!anyNA(stations), !anyDuplicated(stations$code))
  stations <- cbind(stations, project_km(stations$lon, stations$lat))

  list(
    stations = stations,
    profiles = profiles,
    time = data.frame(index = seq_len(HOURS_PER_WEEK), day = factor(day, DAYS), hour = hour,
                      weekend = day %in% c("Sat", "Sun"))
  )
}

#' Equirectangular projection to kilometres around the centre of the stations.
#' Accurate to a few metres over a city the size of Paris.
project_km <- function(lon, lat, origin = c(mean(range(lon)), mean(range(lat)))) {
  earth_km <- 6371.0088
  data.frame(
    x = (lon - origin[1]) * pi / 180 * earth_km * cos(origin[2] * pi / 180),
    y = (lat - origin[2]) * pi / 180 * earth_km
  )
}

#' Descriptors of each station's week, used to describe clusters (never to form them).
station_summary <- function(dat) {
  X <- dat$profiles
  t <- dat$time
  weekday <- !t$weekend
  mean_over <- function(cols) rowMeans(X[, cols, drop = FALSE])
  data.frame(
    id = dat$stations$id,
    mean_fill = rowMeans(X),
    # Working hours against the small hours, on weekdays. Positive: bikes
    # arrive for the day (a place people commute to).
    day_night = mean_over(weekday & t$hour %in% 10:16) - mean_over(weekday & t$hour %in% 1:6),
    weekend_shift = mean_over(t$weekend) - mean_over(weekday)
  )
}
