# karyotype call has no parity fixture. unit-test the map.

# the two arms, in the order the karyotype spec declares them.
ids <- unname(karyotype_inputs(karyotype_spec()))

test_that("predict_sex returns both PCs, a call per sample, and no more", {
  sim <- sim_DNAm(ids, n = 5L)
  out <- predict_sex(sim$DNAm, sim$pheno)

  expect_equal(names(out), c("ID", ids, "predicted_sex"))
  expect_equal(nrow(out), 5L)

  kc <- karyotype_spec()
  labels <- c(
    as.character(kc[["default"]]),
    vapply(kc[["rules"]], function(r) as.character(r[["predicted_sex"]]), "")
  )
  expect_true(all(out$predicted_sex %in% labels))

  # no recorded Female means no comparison columns, with or without a pheno
  expect_false(any(c("recorded_sex", "sex_mismatch") %in% names(out)))
  expect_false("recorded_sex" %in% names(predict_sex(sim$DNAm)))
})

test_that("a sample without both scores is called NA, not the default", {
  # the declared default is a real karyotype, so a gap must not reach it
  sim <- sim_DNAm(ids, n = 6L, Female = TRUE)
  DNAm <- sim$DNAm

  # one arm under the clock floor: no sample can be called
  hole <- clock_scoring_cpgs(ids[[1L]])
  gated <- DNAm[, setdiff(colnames(DNAm), hole[seq_len(round(0.8 *
    length(hole)))]), drop = FALSE]
  out <- suppressWarnings(predict_sex(gated, sim$pheno))
  expect_true(all(is.na(out$predicted_sex)))
  # a call that never happened is never a disagreement
  expect_false(any(out$sex_mismatch))

  # one sample under the sample floor: only that sample loses its call
  DNAm[2L, ] <- NA
  out <- suppressWarnings(predict_sex(DNAm, sim$pheno))
  expect_true(is.na(out$predicted_sex[[2L]]))
  expect_false(any(is.na(out$predicted_sex[-2L])))
})

test_that("a recorded Female is joined by id and compared", {
  sim <- sim_DNAm(ids, n = 8L, Female = TRUE)
  out <- suppressMessages(predict_sex(sim$DNAm, sim$pheno))

  expect_true(all(c("recorded_sex", "sex_mismatch") %in% names(out)))
  expect_equal(
    out$recorded_sex,
    ifelse(sim$pheno$Female == 1, "Female", "Male")
  )
  expect_false(anyNA(out$sex_mismatch))

  # by id, never by row order
  shuffled <- sim$pheno[sample.int(nrow(sim$pheno)), , drop = FALSE]
  b <- suppressMessages(predict_sex(sim$DNAm, shuffled))
  # the sim is unseeded, so the scores differ. the recorded column must not
  expect_equal(out$ID, b$ID)
  expect_equal(out$recorded_sex, b$recorded_sex)
})

test_that("the declared quadrants map, including the corner never tested", {
  skip_on_cran()
  kc <- karyotype_spec()
  scores <- list(
    chrX = c(-1, 1, -1, 1, 0),
    chrY = c(1, 1, -1, -1, 0)
  )
  # expected labels come from evaluating the rule comparisons ("<0" / ">0").
  holds <- function(v, cmp) {
    get(substr(cmp, 1L, 1L))(v, as.numeric(substring(cmp, 2L)))
  }
  label_for <- function(x, y) {
    hit <- Filter(
      function(r) holds(x, r[["chrX"]]) && holds(y, r[["chrY"]]),
      kc[["rules"]]
    )
    if (length(hit)) {
      as.character(hit[[1L]][["predicted_sex"]])
    } else {
      as.character(kc[["default"]])
    }
  }

  # 4th falls to default (no rule). 5th is the exact-zero case.
  expect_equal(
    apply_karyotype(scores, kc),
    mapply(label_for, scores$chrX, scores$chrY, USE.NAMES = FALSE)
  )

  # a sample missing either score gets no call
  missing <- list(chrX = c(NA, -1, NA), chrY = c(1, NA, NA))
  expect_true(all(is.na(apply_karyotype(missing, kc))))

  # swapping the inputs alone would invert every call, silently
  swapped <- kc
  swapped[["inputs"]] <- rev(kc[["inputs"]])
  expect_error(karyotype_inputs(swapped))
})

test_that("only an unambiguous binary disagreement is flagged", {
  skip_on_cran()
  kc <- karyotype_spec()
  pred <- c("Male", "Female", "47,XXY", "45,XO", NA, "Male")
  out <- data.frame(ID = paste0("s", 1:6), stringsAsFactors = FALSE)
  pheno <- data.frame(
    ID = rev(out$ID),
    # aligned to rev(ID): s6 male, s5 na, s4 female, s3 female, s2 female, s1 female
    Female = c(0, NA, 1, 1, 1, 1),
    stringsAsFactors = FALSE
  )

  got <- attach_recorded(out, pheno, "ID", pred, kc)
  expect_equal(
    got$recorded_sex,
    c("Female", "Female", "Female", "Female", NA, "Male")
  )
  # 1: Male vs Female -> flagged. 2: agrees. 3/4: aneuploid. 5: no call and no record. 6: agrees.
  expect_equal(got$sex_mismatch, c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))

  # a Female column that is not 0/1 is refused
  bad <- data.frame(
    ID = c("a", "b"),
    Female = c("F", "M"),
    stringsAsFactors = FALSE
  )
  expect_error(attach_recorded(
    data.frame(ID = c("a", "b"), stringsAsFactors = FALSE),
    bad,
    "ID",
    c("Female", "Male"),
    kc
  ))
})
