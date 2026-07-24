# SystemsAge: organ sub-clocks plus Age_prediction / SystemsAge composites

# polynomial evaluation, lowest degree first
sa_poly <- function(L, coef) {
  out <- rep(0, length(L))
  for (k in seq_along(coef)) {
    out <- out + coef[[k]] * L^(k - 1L)
  }
  out
}

# batched scorer for the SystemsAge group
score_systemsage_group <- function(
  ids,
  usable,
  DNAm,
  partial_cache,
  pheno,
  packs
) {
  pack <- clock_pack(ids[[1]], packs)
  design <- pack_design(pack, usable, DNAm, partial_cache)
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  composites <- intersect(ids, c("Age_prediction", "SystemsAge"))
  organs_req <- setdiff(ids, composites)

  record <- function(id, score_vec) {
    score_matrix(score_vec, sample_id, id)
  }

  out <- vector("list", length(ids))
  names(out) <- ids

  if (length(organs_req)) {
    Mo <- pack[["organs"]]
    rownames(Mo) <- pack[["cpgs"]]
    O <- pack_linpred(design, Mo, organs_req)
    for (org in organs_req) {
      out[[org]] <- record(org, O[, org] + clock_intercept(org))
    }
  }

  if (length(composites)) {
    Ma <- matrix(
      as.numeric(pack[["age"]]),
      ncol = 1L,
      dimnames = list(pack[["cpgs"]], "age")
    )
    age_matmul <- as.numeric(pack_linpred(design, Ma, "age"))

    if ("Age_prediction" %in% composites) {
      L <- age_matmul + systemsage_age_intercept("Age_prediction")
      out[["Age_prediction"]] <- record(
        "Age_prediction",
        sa_poly(L, systemsage_poly("Age_prediction", "score"))
      )
    }

    if ("SystemsAge" %in% composites) {
      id <- "SystemsAge"
      L <- age_matmul + systemsage_age_intercept(id)
      ap_scaled <- sa_poly(L, systemsage_poly(id, "ap_scaled"))

      order <- systemsage_stack_order(id)
      organs_pca <- setdiff(order, "Age_prediction")
      Ms <- pack[["systems"]]
      rownames(Ms) <- pack[["cpgs"]]
      S <- sweep(
        pack_linpred(design, Ms, organs_pca),
        2L,
        systemsage_raw_intercepts(id)[organs_pca],
        "+"
      )

      sysscores <- matrix(0, n, length(order), dimnames = list(NULL, order))
      sysscores[, "Age_prediction"] <- ap_scaled
      sysscores[, organs_pca] <- S[, organs_pca]

      pca <- systemsage_pca(id, packs, order)
      cs <- sweep(sweep(sysscores, 2L, pca$center, "-"), 2L, pca$scale, "/")
      pcs <- cs %*% pca$rotation
      out[[id]] <- record(
        id,
        as.numeric(systemsage_final_intercept(id) + pcs %*% pca$model)
      )
    }
  }
  out
}
