#include <Rcpp.h>
#include <cmath>
using namespace Rcpp;

// fill non-finite entries with the column mean (same as col_stats).
// [[Rcpp::export]]
void fill_imp_col(SEXP obj, NumericVector mean_vec)
{
  // SEXP, not NumericMatrix: a coerced copy would be filled and dropped,
  // leaving the caller an unimputed cache and no error to read.
  if (TYPEOF(obj) != REALSXP || !Rf_isMatrix(obj))
  {
    stop("obj must be a double matrix");
  }

  const NumericMatrix mat(obj);

  if (mean_vec.size() != mat.ncol())
  {
    stop("mean_vec must have length ncol(obj)");
  }

  const R_xlen_t nc = mat.ncol(), nr = mat.nrow();
  double *x = REAL(obj);
  const double *mu = mean_vec.begin();

  for (R_xlen_t j = 0; j < nc; ++j)
  {
    double *col = x + j * nr;
    const double m = mu[j];
    for (R_xlen_t i = 0; i < nr; ++i)
    {
      const double v = col[i];
      col[i] = std::isfinite(v) ? v : m;
    }
  }
}
