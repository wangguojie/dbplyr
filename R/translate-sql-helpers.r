#' Create an sql translator
#'
#' When creating a package that maps to a new SQL based src, you'll often
#' want to provide some additional mappings from common R commands to the
#' commands that your tbl provides. These three functions make that
#' easy.
#'
#' @section Helper functions:
#'
#' `sql_infix()` and `sql_prefix()` create default SQL infix and prefix
#' functions given the name of the SQL function. They don't perform any input
#' checking, but do correctly escape their input, and are useful for
#' quickly providing default wrappers for a new SQL variant.
#'
#' @keywords internal
#' @seealso [win_over()] for helper functions for window functions.
#' @param scalar,aggregate,window The three families of functions than an
#'   SQL variant can supply.
#' @param ...,.funs named functions, used to add custom converters from standard
#'  R functions to sql functions. Specify individually in `...`, or
#'  provide a list of `.funs`
#' @param .parent the sql variant that this variant should inherit from.
#'   Defaults to `base_agg` which provides a standard set of
#'   mappings for the most common operators and functions.
#' @param f the name of the sql function as a string
#' @param n for `sql_infix()`, an optional number of arguments to expect.
#'   Will signal error if not correct.
#' @seealso [sql()] for an example of a more customised sql
#'   conversion function.
#' @export
#' @examples
#' # An example of adding some mappings for the statistical functions that
#' # postgresql provides: http://bit.ly/K5EdTn
#'
#' postgres_agg <- sql_translator(.parent = base_agg,
#'   cor = sql_prefix("corr"),
#'   cov = sql_prefix("covar_samp"),
#'   sd =  sql_prefix("stddev_samp"),
#'   var = sql_prefix("var_samp")
#' )
#' postgres_var <- sql_variant(
#'   base_scalar,
#'   postgres_agg
#' )
#'
#' translate_sql(cor(x, y), variant = postgres_var)
#' translate_sql(sd(income / years), variant = postgres_var)
#'
#' # Any functions not explicitly listed in the converter will be translated
#' # to sql as is, so you don't need to convert all functions.
#' translate_sql(regr_intercept(y, x), variant = postgres_var)
sql_variant <- function(scalar = sql_translator(),
                        aggregate = sql_translator(),
                        window = sql_translator()) {
  stopifnot(is.environment(scalar))
  stopifnot(is.environment(aggregate))
  stopifnot(is.environment(window))

  # Need to check that every function in aggregate also occurs in window
  missing <- setdiff(ls(aggregate), ls(window))
  if (length(missing) > 1) {
    warn(paste0(
      "Translator is missing window functions:\n",
      paste0(missing, collapse = ", ")
    ))
  }

  structure(
    list(scalar = scalar, aggregate = aggregate, window = window),
    class = "sql_variant"
  )
}

is.sql_variant <- function(x) inherits(x, "sql_variant")

#' @export
print.sql_variant <- function(x, ...) {
  wrap_ls <- function(x, ...) {
    vars <- sort(ls(envir = x))
    wrapped <- strwrap(paste0(vars, collapse = ", "), ...)
    if (identical(wrapped, "")) return()
    paste0(wrapped, "\n", collapse = "")
  }

  cat("<sql_variant>\n")
  cat(wrap_ls(
    x$scalar,
    prefix = "scalar:    "
  ))
  cat(wrap_ls(
    x$aggregate,
    prefix = "aggregate: "
  ))
  cat(wrap_ls(
    x$window,
    prefix = "window:    "
  ))
}

#' @export
names.sql_variant <- function(x) {
  c(ls(envir = x$scalar), ls(envir = x$aggregate), ls(envir = x$window))
}

#' @export
#' @rdname sql_variant
sql_translator <- function(..., .funs = list(),
                           .parent = new.env(parent = emptyenv())) {
  funs <- c(list(...), .funs)
  if (length(funs) == 0) return(.parent)

  list2env(funs, copy_env(.parent))
}

copy_env <- function(from, to = NULL, parent = parent.env(from)) {
  list2env(as.list(from), envir = to, parent = parent)
}

#' @rdname sql_variant
#' @export
sql_infix <- function(f) {
  assert_that(is_string(f))

  f <- toupper(f)
  function(x, y) {
    build_sql(x, " ", sql(f), " ", y)
  }
}

#' @rdname sql_variant
#' @export
sql_prefix <- function(f, n = NULL) {
  assert_that(is_string(f))

  f <- toupper(f)
  function(..., na.rm) {
    if (!missing(na.rm)) {
      message("na.rm not needed in SQL: NULL are always dropped", call. = FALSE)
    }

    args <- list(...)
    if (!is.null(n) && length(args) != n) {
      stop(
        "Invalid number of args to SQL ", f, ". Expecting ", n,
        call. = FALSE
      )
    }
    if (any(names2(args) != "")) {
      warning("Named arguments ignored for SQL ", f, call. = FALSE)
    }
    build_sql(sql(f), args)
  }
}

#' @rdname sql_variant
#' @export
sql_not_supported <- function(f) {
  assert_that(is_string(f))

  f <- toupper(f)
  function(...) {
    stop(f, " is not available in this SQL variant", call. = FALSE)
  }
}

#' @rdname sql_variant
#' @export
sql_cast <- function(type) {
  function(x) {
    build_sql("CAST(", x, " AS ", sql(type), ")")
  }
}
