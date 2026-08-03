# karyotype call has no parity fixture. unit-test the map.

test_that("the declared quadrants map, including the corner never tested", {
  kc <- karyotype_spec()
  scores <- list(
    chrX = c(-1, 1, -1, 1, 0),
    chrY = c(1, 1, -1, -1, 0)
  )
  # 4th falls to default (no rule). 5th is the exact-zero case.
  expect_equal(
    apply_karyotype(scores, kc),
    c("Male", "47,XXY", "45,XO", "Female", "Female")
  )
})

test_that("a sample missing either score gets no call", {
  kc <- karyotype_spec()
  scores <- list(chrX = c(NA, -1, NA), chrY = c(1, NA, NA))
  expect_true(all(is.na(apply_karyotype(scores, kc))))
})

test_that("operand order is checked against the input ids", {
  kc <- karyotype_spec()
  # swapping the inputs alone would invert every call, silently
  swapped <- kc
  swapped[["inputs"]] <- rev(kc[["inputs"]])
  expect_error(karyotype_inputs(swapped))
})

test_that("predict_sex returns both PCs and a call per sample", {
  ids <- c("DNAmSex_Wang_ChrX", "DNAmSex_Wang_ChrY")
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
})

# the recorded-sex comparison

test_that("no Female column means no comparison columns", {
  ids <- c("DNAmSex_Wang_ChrX", "DNAmSex_Wang_ChrY")
  sim <- sim_DNAm(ids, n = 5L)
  out <- predict_sex(sim$DNAm, sim$pheno)
  expect_false("recorded_sex" %in% names(out))
  expect_false("sex_mismatch" %in% names(out))

  # and no pheno at all is the same
  expect_false("recorded_sex" %in% names(predict_sex(sim$DNAm)))
})

test_that("a recorded Female becomes the rule table's own labels", {
  ids <- c("DNAmSex_Wang_ChrX", "DNAmSex_Wang_ChrY")
  sim <- sim_DNAm(ids, n = 6L, Female = TRUE)
  out <- suppressMessages(predict_sex(sim$DNAm, sim$pheno))

  expect_true(all(c("recorded_sex", "sex_mismatch") %in% names(out)))
  expect_equal(
    out$recorded_sex,
    ifelse(sim$pheno$Female == 1, "Female", "Male")
  )
  expect_type(out$sex_mismatch, "logical")
  expect_false(anyNA(out$sex_mismatch))
})

test_that("the recorded sex is joined by id, not by row order", {
  ids <- c("DNAmSex_Wang_ChrX", "DNAmSex_Wang_ChrY")
  sim <- sim_DNAm(ids, n = 8L, Female = TRUE)
  shuffled <- sim$pheno[sample.int(nrow(sim$pheno)), , drop = FALSE]

  a <- suppressMessages(predict_sex(sim$DNAm, sim$pheno))
  b <- suppressMessages(predict_sex(sim$DNAm, shuffled))
  # the sim is unseeded, so the scores differ; the recorded column must not
  expect_equal(a$ID, b$ID)
  expect_equal(a$recorded_sex, b$recorded_sex)
})

test_that("only an unambiguous binary disagreement is flagged", {
  kc <- karyotype_spec()
  pred <- c("Male", "Female", "47,XXY", "45,XO", NA, "Male")
  out <- data.frame(
    ID = paste0("s", 1:6),
    stringsAsFactors = FALSE
  )
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
  # 1: Male vs Female -> flagged. 2: agrees. 3/4: aneuploid. 5: no call and no
  # record. 6: agrees.
  expect_equal(got$sex_mismatch, c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
})

test_that("a disagreement is reported, and agreement says nothing", {
  out <- data.frame(ID = "s1", sex_mismatch = TRUE, stringsAsFactors = FALSE)
  expect_message(say_mismatch(out))
  out$sex_mismatch <- FALSE
  expect_silent(say_mismatch(out))
})

test_that("a Female column that is not 0/1 is refused", {
  kc <- karyotype_spec()
  out <- data.frame(ID = c("a", "b"), stringsAsFactors = FALSE)
  pheno <- data.frame(
    ID = c("a", "b"),
    Female = c("F", "M"),
    stringsAsFactors = FALSE
  )
  expect_error(attach_recorded(out, pheno, "ID", c("Female", "Male"), kc))
})
