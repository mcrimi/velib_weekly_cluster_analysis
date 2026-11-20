# Pipeline: raw data -> cleaned profiles -> PCA and clustering -> validation ->
# JSON for the web page -> rendered report. Run with `targets::tar_make()`.

library(targets)
library(tarchetypes)

tar_option_set(packages = c("cluster", "mclust"))
tar_source("R")

list(
  tar_target(raw_file, "data/raw/velib.Rdata", format = "file"),
  tar_target(velib, clean_velib(load_raw(raw_file))),
  tar_target(summary, station_summary(velib)),

  # Structure
  tar_target(pca, fit_pca(velib$profiles)),
  tar_target(components_90, components_for(velib$profiles, 0.9)),
  tar_target(kmeans_fits, lapply(K_RANGE, function(k) fit_kmeans(velib$profiles, k))),
  tar_target(ward, fit_ward(velib$profiles)),
  tar_target(mixtures, fit_mixtures(pca_scores(pca, velib$profiles, 5))),

  # How many clusters, and how real are they?
  tar_target(gap, gap_statistic(velib$profiles, B = 50)),
  tar_target(stability, lapply(kmeans_fits, function(f) {
    bootstrap_stability(velib$profiles, f$cluster, B = 100)
  })),
  tar_target(validity, validity_table(velib$profiles, kmeans_fits, ward, mixtures, gap, stability)),
  tar_target(benchmark, null_benchmark(velib$profiles, B = 50)),

  # Geography, which the clustering never saw
  tar_target(neighbours, nearest_neighbours(velib$stations[c("x", "y")], k = 6)),
  tar_target(spatial, spatial_table(velib, kmeans_fits, neighbours)),
  tar_target(moran, lapply(1:2, function(j) {
    morans_i(pca_scores(pca, velib$profiles, 2)[, j], neighbours)
  })),
  tar_target(bonus, bonus_table(velib, summary, kmeans_fits[[3]]$cluster)),

  # Exports for the web page
  tar_target(stations_json,
             export_stations(velib, summary, pca, kmeans_fits, "web/data/stations.json"),
             format = "file"),
  tar_target(story_json,
             export_story(velib, summary, pca, components_90, kmeans_fits, validity, benchmark,
                          gap, mixtures, spatial, moran, bonus, "web/data/story.json"),
             format = "file"),
  tar_target(fixtures_json, export_fixtures(stations_json, "web/test/fixtures.json"),
             format = "file"),

  # Report
  tar_quarto(report, "report/index.qmd", quiet = TRUE)
)
