root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
for (f in list.files(file.path(root, "R"), full.names = TRUE)) source(f)
velib <- clean_velib(load_raw(file.path(root, "data", "raw", "velib.Rdata")))
X <- velib$profiles

# Three well-separated groups of flat profiles, for tests that need a known answer.
toy <- withr::with_seed(1, {
  level <- rep(c(0.1, 0.5, 0.9), each = 40)
  list(X = matrix(level + stats::rnorm(120 * 12, sd = 0.02), 120), truth = rep(1:3, each = 40))
})
