### lmer functions stuff starts here
#' mincified version of lmer from lme4
#'
#' mincLmer should be used the same way as a straight lmer call, except
#' that the left hand side of the equation contains minc filenames rather than
#' an actual response variable.
#'
#' @param formula the lmer formula, filenames go on left hand side
#' @param data the data frame, all items in formula should be in here
#' @param mask the mask within which lmer is solved
#' @param parallel how many processors to run on (default=single processor).
#' Specified as a two element vector, with the first element corresponding to
#' the type of parallelization, and the second to the number
#' of processors to use. For local running set the first element to "local" or "snowfall"
#' for back-compatibility, anything else will be run with batchtools see \link{pMincApply}.
#' Leaving this argument NULL runs sequentially and may take a long time. 

#' @param REML whether to use use Restricted Maximum Likelihood or Maximum Likelihood
#' @param control lmer control function
#' @param start lmer start function
#' @param verbose lmer verbosity control
#' @param temp_dir A directory to create temporary mask and registry files if 
#' \code{parallel = c("sge", n)}. This should not be \code{tempdir()} so that workers can see
#' these files. Defaults to the current working directory.
#' @param safely whether or not to wrap the per-voxel lmer code in an exception catching
#' block (\code{tryCatch}), when TRUE this will downgrade errors to warnings and return
#' NA for the result.
#' @param summary_type Either one of
#' \itemize{
#'   \item{fixef: default and equivalent to older versions of RMINC, returns fixed effect coefficients and t-values}
#'   \item{ranef: returns random effect coefficients and t-values}
#'   \item{both: both fixed and random effects}
#'   \item{anova: return the F-statistic for each fixed effect}
#'} or a function to be used to generate the summary
#' @param weights weights to be applied to each observation
#' @param cleanup Whether or not to cleanup registry files after a queue parallelized 
#' run
#' @param resources A list of resources to use for the jobs, for example
#' \code{ list(nodes = 1, memory = "8G", walltime = "01:00:00") }. See
#' \code{system.file("parallel/pbs_script.tmpl", package = "RMINC")} and
#' \code{system.file("parallel/sge_script.tmpl", package = "RMINC")} for
#' more examples
#' @param conf_file A batchtools configuration file
#' @return a matrix where rows correspond to number of voxels in the file and columns to
#' the number of terms in the formula, with both the beta coefficient and the t-statistic
#' being returned. In addition, an extra column keeps the log likelihood, and another
#' whether the mixed effects fitting converged or not.
#'
#' @details mincLmer provides an interface to running linear mixed effects models at every
#' voxel. Unlike standard mincLm, however, testing hypotheses in linear mixed effects models
#' is more difficult, since the denominator degrees of freedom are more difficult to
#' determine. RMINC provides two alternatives: (1) estimating degrees of freedom using the
#' \code{\link{mincLmerEstimateDF}} function, and (2) comparing two separate models using
#' \code{\link{mincLogLikRatio}} (which in turn can be corrected using
#' \code{\link{mincLogLikRatioParametricBootstrap}}). For the most likely models - longitudinal
#' models with a separate intercept or separate intercept and slope per subject - both of these
#' approximations are likely correct. Be careful in using these approximations if
#' using more complicated random effects structures. \cr
#' If you encounter memory issues, it could be due to minc file caching.
#' Consider trying with the environment variable MINC_FILE_CACHE_MB set to
#' a small value like 1.
#'
#' @seealso \code{\link{lmer}} for description of lmer and lmer formulas; \code{\link{mincLm}}
#' @examples
#' \dontrun{
#' vs <- mincLmer(filenames ~ age + sex + (age|id), data=gf, mask="mask.mnc")
#' mincWriteVolume(vs, "age-term.mnc", "tvalue-age")
#' # run in parallel with multiple processors on the local machine
#' vs <- mincLmer(filenames ~ age + sex + (age|id), 
#'                data=gf, 
#'                mask="mask.mnc", 
#'                parallel=c("snowfall", 4))
#' # run in parallel with multiple processors over the sge batch queueing system
#' vs <- mincLmer(filenames ~ age + sex + (age|id), 
#'                data=gf, 
#'                mask="mask.mnc", 
#'                parallel=c("sge", 4))
#' # estimate degrees of freedom
#' vs <- mincLmerEstimateDF(vs)
#' # correct for multiple comparisons using the False Discovery Rate
#' (qvals <- mincFDR(vs))
#' # generate another model with a more complex curve for the age term
#' library(splines)
#' vs2 <- mincLmer(filenames ~ ns(age,2) + sex + (age|id), data=gf, mask="mask.mnc")
#' # see if that more complex age term was worth it
#' modelCompare <- mincLogLikRatio(vs, vs2)
#' mincFDR(modelCompare)
#' # see if there was any bias in those p-value estimates (takes a few minutes)
#' modelCompare <- mincLogLikRatioParametricBootstrap(modelCompare)
#' mincFDR(modelCompare)
#' }
#' @export
mincLmer <- function(formula, data, mask, parallel=NULL,
                     REML=TRUE, control=lmerControl(), start=NULL, 
                     verbose=0L, temp_dir = getwd(), safely = FALSE, 
                     cleanup = TRUE, summary_type = "fixef"
                   , weights = NULL
                   , resources = list()
                   , conf_file = getOption("RMINC_BATCH_CONF")) {
  
  # the outside part of the loop - setting up various matrices, etc., whatever that is
  # constant for all voxels goes here
  if(!is.character(mask)) stop("A character mask must be provided to run mincLmer")
  # code ripped straight from lme4::lmer
  mc <- mcout <- match.call()
  #mc$control <- lmerControl() #overrides user input control
  mc[[1]] <- quote(lme4::lFormula)
  
  # remove lme4 unknown arguments, since lmer does not know about them and keeping them
  # generates obscure warning messages
  mc <- mc[!names(mc) %in% c("mask", "parallel", "temp_dir", "safely", "cleanup", "summary_type")]
  
  lmod <- eval(mc, parent.frame(1L))
  mincFileCheck(lmod$fr[,1])
  
  # code ripped from lme4:::mkLmerDevFun
  rho <- new.env(parent = parent.env(environment()))
  rho$pp <- do.call(merPredD$new, c(lmod$reTrms[c("Zt", "theta", 
                                                  "Lambdat", "Lind")],
                                    n = nrow(lmod$X), list(X = lmod$X)))
  REMLpass <- if (REML) 
    ncol(lmod$X)
  else 0L
  
  
  mincLmerList <- list(lmod, mcout, control, start, verbose, rho, REMLpass)
  
  # for some reason there is a namespace issue if I call diag directly, but only if inside
  # a function that is part of RMINC (i.e. if I source the code it works fine). So here's a
  # workaround to get the method first, give it a new name, and assign to global namespace.
  ###tmpDiag <<- getMethod("diag", "dsyMatrix")
  #fmincLmerOptimizeAndExtract <<- mincLmerOptimizeAndExtract
  
  #Set the slab dimensions such that it reads one slice at a time along dim 1
  
  slab_dims <- minc.dimensions.sizes(lmod$fr[1,1])
  slab_dims[1] <- 1
  
  summary_fun <- summary_type
  if(is.character(summary_type) && length(summary_type) == 1)
    summary_fun <- switch(summary_type
                        , fixef = fixef_summary
                        , ranef = ranef_summary
                        , both = effect_summary
                        , anova = anova_summary
                        , stop("invalid summary type specified"))

  if(!is.function(summary_fun))
    stop("summary_type must be a string specifying a summary, or a function")
  
  mincLmerOptimizeAndExtractSafely <-
    function(x, mincLmerList, summary_fun){
      tryCatch(mincLmerOptimizeAndExtract(x, mincLmerList, summary_fun),
               error = function(e){warning(e); return(NA)})
    }
  
  optimizer_fun <- 
    `if`(safely, mincLmerOptimizeAndExtractSafely, mincLmerOptimizeAndExtract)
  
  if (!is.null(parallel)) {
    # a vector with two elements: the methods followed by the # of workers
    if (parallel[1] %in% c("local", "snowfall")) {
      out <- mcMincApply(lmod$fr[,1],
                         optimizer_fun,
                         mincLmerList = mincLmerList,
                         filter_masked = TRUE,
                         mask = mask,
                         cores = as.numeric(parallel[2]),
                         slab_sizes = slab_dims,
                         summary_fun = summary_fun,
                         cleanup = cleanup)
    }
    else {
      out <- qMincApply(lmod$fr[,1],
                        optimizer_fun,
                        mincLmerList = mincLmerList,
                        filter_masked = TRUE,
                        temp_dir = temp_dir,
                        cores = 1,
                        mask = mask,
                        batches = as.numeric(parallel[2]),
                        slab_sizes = slab_dims,
                        summary_fun = summary_fun,
                        cleanup = cleanup,
                        registry_name = new_file("mincLmer_registry"),
                        resources = resources,
                        conf_file = conf_file
                        )
    } 
  }
  else {
    out <- mincApplyRCPP(lmod$fr[,1], # assumes that the formula was e.g. filenames ~ effects
                         optimizer_fun,
                         mincLmerList = mincLmerList,
                         mask = mask,
                         summary_fun = summary_fun,
                         slab_sizes = slab_dims)
  }
  
  ## Result post processing
  out[is.infinite(out)] <- 0            #zero out infinite values produced by vcov
  
  #termnames <- colnames(lmod$X)
  #betaNames <- paste("beta-", termnames, sep="")
  #tnames <- paste("tvalue-", termnames, sep="")
  #colnames(out) <- c(betaNames, tnames, "logLik", "converged")
  
  
  # generate some random numbers for a single fit in order to extract some extra info
  mmod <- mincLmerOptimize(rnorm(length(lmod$fr[,1])), mincLmerList)
  
  res_cols <- colnames(out)
  attr(out, "stat-type") <- ## Handle all possible output types
    check_stat_type(res_cols, summary_type)

  # get the DF for future logLik ratio tests; code from lme4:::npar.merMod
  attr(out, "logLikDF") <- length(mmod@beta) + length(mmod@theta) + mmod@devcomp[["dims"]][["useSc"]]
  attr(out, "REML") <- REML
  attr(out, "mask") <- mask
  attr(out, "data") <- data
  attr(out, "mincLmerList") <- mincLmerList
  class(out) <- c("mincLmer", "mincMultiDim", "matrix")
  
  return(out)
}

#' Estimate the degrees of freedom for parameters in a mincLmer model
#'
#' There is much uncertainty in how to compute p-values for mixed-effects
#' statistics, related to the correct calculation of the degrees of freedom
#' of the model (see here \url{http://glmm.wikidot.com/faq#df}). mincLmer by
#' default does not return the degrees of freedom as part of its model, instead
#' requiring an explicit call to a separate function (such as this one).
#' The implementation here is the Satterthwaite approximation. This approximation
#' is computed from the data, to avoid the significant run-time requirement of computing
#' it separate for every voxel, here it is only computed on a small number of voxels
#' within the mask and the median DF returned for every variable.
#' 
#' @param model the output of mincLmer
#'
#' @return the same mincLmer model, now with degrees of freedom set
#'
#' @seealso \code{\link{mincLmer}} for mixed effects modelling, \code{\link{mincFDR}}
#' for multiple comparisons corrections.
#'
#' @examples
#' \dontrun{
#' vs <- mincLmer(filenames ~ age + sex + (age|id), data=gf, mask="mask.mnc")
#' vs <- mincLmerEstimateDF(vs)
#' qvals <- mincFDR(vs, mask=attr(vs, "mask"))
#' qvals
#' }
#' @export
mincLmerEstimateDF <- function(model) {
  # set the DF based on the Satterthwaite approximation
  
  mincLmerList <- attr(model, "mincLmerList")
  mask <- attr(model, "mask")
  
  # estimated DF depends on the input data. Rather than estimate separately at every voxel,
  # instead select a small number of voxels and estimate DF for those voxels, then keep the
  # min
  nvoxels <- 50
  rvoxels <- mincSelectRandomVoxels(mask, nvoxels)
  dfs <- matrix(nrow=nvoxels, ncol=sum(attr(model, "stat-type") %in% "tlmer"))
  original_data <- attr(model, "data")
  
  ## It seems LmerTest cannot compute the deviance function for mincLmers
  ## in the current version, instead extract the model components from
  ## the mincLmerList and re-fit the lmers directly at each structure,
  ## Slower but yeilds the correct result
  lmod <- mincLmerList[[1]]
  LHS <- as.character(lmod$formula[[2]])
  form <- update(lmod$formula, RMINC_DUMMY_LHS ~ .)
  #environment(model_form) <- environment()
  
  filenames <- unique(mincLmerList[[1]]$fr[,1])
  row_file_match <- match(original_data[[LHS]], filenames)
  
  for (i in 1:nvoxels) {
    rand_inds <- rvoxels[i,]
    voxel_data <- mincGetVoxel(filenames, rand_inds)
    
    original_data$RMINC_DUMMY_LHS <- voxel_data[row_file_match]

    ## Work around for slowness in recent lme4, fixed in upstream lme4
    ## thanks to https://github.com/lme4/lme4/issues/410#issuecomment-311092416
    model_env <- list2env(original_data)
    environment(form) <- model_env
    
    mmod <-
      lmerTest::lmer(form, REML = lmod$REML,
                     start = mincLmerList[[4]], control = mincLmerList[[3]],
                     verbose = mincLmerList[[5]])
    
    dfs[i,] <- 
      suppressMessages(
        tryCatch(summary(mmod)$coefficients[,"df"]
                 , error = function(e){ 
                   warning("Unable to estimate DFs for voxel ("
                           , paste0(rand_inds, collapse = ", ")
                           , ")"
                           , call. = FALSE)
                   NA}))
  }
  
  df <- apply(dfs, 2, median, na.rm = TRUE)
  cat("Mean df: ", apply(dfs, 2, mean, na.rm = TRUE), "\n")
  cat("Median df: ", apply(dfs, 2, median, na.rm = TRUE), "\n")
  cat("Min df: ", apply(dfs, 2, min, na.rm = TRUE), "\n")
  cat("Max df: ", apply(dfs, 2, max, na.rm = TRUE), "\n")
  cat("Sd df: ", apply(dfs, 2, sd, na.rm = TRUE), "\n")
  
  attr(model, "df") <- df

  return(model)
}
# the actual optimization of the mixed effects models; everything that has to be recomputed
# for every voxel goes here. Works on x (each voxel is assigned x during the loop), and
# assumes that all the other info is in a variable called mincLmerList in the global
# environment. This last part is a hack to get around the lack of multiple function arguments
# for mincApply and friends.
mincLmerOptimize <- function(x, mincLmerList) {
  # code ripped straight from lme4::lmer
  # assignments from global variable set in mincLmer
  lmod <- mincLmerList[[1]]
  mcout <- mincLmerList[[2]]
  control <- mincLmerList[[3]]
  start <- mincLmerList[[4]]
  verbose <- mincLmerList[[5]]
  rho <- mincLmerList[[6]]
  REMLpass <- mincLmerList[[7]]
  
  # assign the vector of voxel values
  lmod$fr[,1] <- x
  
  mmod <- mincLmerOptimizeCore(rho, lmod, REMLpass, verbose, control, mcout, start, reinit=FALSE)
  # the rho$pp merModP object needs to be reinitialized at (to me) mysterious times. That is
  # quite time consuming, however, so only do so if something did not converge.
  if (length(attr(mmod,"optinfo")$conv$lme4$code) != 0) {
    #cat("Restarting ... \n")
    mmod <- mincLmerOptimizeCore(rho, lmod, REMLpass, verbose, control, mcout, start, reinit=TRUE)
  }
  
  return(mmod)
}

# the core code that does the optimization. Only reason it is not part of mincLmerOptimize
# is to allow for the reinitializtion in case of convergence error  
mincLmerOptimizeCore <- function(rho, lmod, REMLpass, verbose, control, mcout, start, reinit=F) {
  # finish building the dev function by adding the response term
  # code from lme4:::mkLmerDevFun
  # this code is quite slow; I'm baffled about when it's needed, as most of the
  # time it can stay outside the loop, but occasionally gives weird errors
  # if inside. So wrapped inside that reinit bit:
  if (reinit) {
    form <- mcout[[2]]
    lmod$reTrms <- mkReTrms(findbars(form[[length(form)]]), lmod$fr)
    rho$pp <- do.call(merPredD$new, c(lmod$reTrms[c("Zt", "theta", 
                                                    "Lambdat", "Lind")],
                                      n = nrow(lmod$X), list(X = lmod$X)))
  }
  
  # rho$resp <- mkRespMod(lmod$fr, REML = REMLpass)
  # devfun <- lme4:::mkdevfun(rho, 0L, verbose = verbose, control = control)
  # theta <- lme4:::getStart(lmod$start, lmod$reTrms$lower, rho$pp)
  # if (length(rho$resp$y) > 0) 
  #   devfun(rho$pp$theta)
  # rho$lower <- lmod$reTrms$lower
  
  # kept the old full mkLmerDevFun call around here in case the divided call
  # ends up with unexpected side effects down the road.
  # devfun <- do.call(mkLmerDevfun, c(lmod,
  #                                  list(start = start,
  #                                       verbose = verbose,
  #                                       control = control)))
  devfun <- mkLmerDevfun(lmod$fr, lmod$X, lmod$reTrms, lmod$REML, start, verbose, control)
  
  # the optimization of the function - straight from lme4:::lmer
  opt <- optimizeLmer(devfun, optimizer = control$optimizer, 
                      restart_edge = control$restart_edge,
                      boundary.tol = control$boundary.tol, 
                      control = control$optCtrl, verbose = verbose,
                      start = start, 
                      calc.derivs = control$calc.derivs,
                      use.last.params = control$use.last.params)
  cc <- checkConv(attr(opt, "derivs"), opt$par,
                   ctrl = control$checkConv, 
                  lbound = environment(devfun)$lower)
  mmod <- mkMerMod(environment(devfun), opt, lmod$reTrms,
                   fr = lmod$fr, mcout, lme4conv = cc)
  return(mmod)
}

check_stat_type <- function(stat, summary_type){
  if(!is.character(summary_type))
    summary_type <- "unknown"
  
  case_when(stat == "logLik" ~ "logLik"
          , stat == "converged" ~ "converged"
          , summary_type == "anova" ~ "flmer"
          , grepl("^tvalue-", stat) & summary_type == "ranef" ~ "rand-tlmer"
          , grepl("^beta-", stat) & summary_type == "ranef" ~ "rand-beta"
          , grepl("^tvalue-", stat) ~ "tlmer"
          , grepl("^beta-", stat) ~ "beta"
          , grepl("^rand-beta-", stat) ~ "rand-beta"
          , grepl("^rand-tvalue-", stat) ~ "rand-tlmer"
          , TRUE ~ "unknown")
  }
  

# takes a merMod object, gets beta, t, and logLikelihood values, and
# returns them as a vector
fixef_summary <- function(mmod) {
  se <- tryCatch({ # vcov sometimes complains that matrix is not positive definite
    sqrt(Matrix::diag(vcov(mmod)))
  }, warning=function(w) {
    return(0)
  }, error=function(e) {
    return(0)
  })
  fe <- fixef(mmod)
  effects <- names(fe)
  t <- fe / se # returns Inf if se=0 (see error handling above); mincLmer removes Inf
  ll <- logLik(mmod)
  names(fe) <- paste0("beta-", effects)
  names(t) <- paste0("tvalue-", effects)
  # the convergence return value (I think; need to verify) - should be 0 if it converged
  converged <- length(attr(mmod,"optinfo")$conv$lme4$code) == 0
  return(c(fe,t, logLik = logLik(mmod), converged = converged))
}

ranef_summary <- 
  function(mmod){
    
    gather_matrix <- 
      function(m, val_name){
        as.data.frame(m) %>%
          mutate(group = rownames(m)) %>%
          gather_("effect", val_name, colnames(m))  
      }
    
    
    eff <- ranef(mmod, condVar = TRUE)
    
    betas_and_ts <-
      mapply(function(e, group_name){
        condVar <- attr(e, "postVar")
        group_se <- apply(condVar, 3, function(v) sqrt(diag(as.matrix(v))))
        
        if(is.null(dim(group_se))){ #deal with the dropped dimension in case of two group ranef 
          group_se <- matrix(group_se, nrow = length(group_se))
        } else {
          group_se <- t(group_se)
        }
        
        dimnames(group_se) <- dimnames(e)
        group_se <- 
          gather_matrix(group_se, "se")
        
        e <- 
          gather_matrix(e, "beta")
        
        t_mat <- 
          inner_join(group_se, e, by = c("group", "effect")) %>%
          mutate_(tvalue = ~ beta / se
                  , grouping = ~ group_name
                  , se = ~ NULL) %>%
          gather_("var", "value", c("tvalue", "beta")) %>%
          unite_("groupingXgroup", c("grouping", "group"), sep = "") %>%
          unite_("varXeffectXgroupingXgroup", c("var", "effect", "groupingXgroup"), sep = "-") %>%
          spread_("varXeffectXgroupingXgroup", "value") %>%
          as.matrix %>%
          .[1,]
      }, e = eff, group_name = names(eff), SIMPLIFY = FALSE) %>%
      Reduce(c, ., NULL)
    
    converged <- length(attr(mmod,"optinfo")$conv$lme4$code) == 0
    c(betas_and_ts, logLik = logLik(mmod), converged = converged)
  }

effect_summary <-
  function(mmod){
    fix <- fixef_summary(mmod)
    #remove converged and logLik, these will come from the random effects
    fix <- fix[! names(fix) %in% c("converged", "logLik")] 
    
    ran <- ranef_summary(mmod)
    names(ran) <- names(ran) %>% sub("beta", "rand-beta", .) %>% sub("tvalue", "rand-tvalue", .)
    
    c(fix, ran)
  }

anova_summary <-
  function(mmod){
    converged <- length(attr(mmod,"optinfo")$conv$lme4$code) == 0
    
    anova(mmod) %>% 
      t %>% 
      .["F value", , drop = FALSE] %>%
      setNames(paste0("F-", colnames(.))) %>%
      c(logLik = logLik(mmod), converged = converged)
  }

mincLmerOptimizeAndExtract <- function(x, mincLmerList, summary_function = fixef_summary) {
  mmod <- mincLmerOptimize(x, mincLmerList)
  return(summary_function(mmod))
}

#' run log likelihood ratio tests for different mincLmer objects
#'
#' Computes the log likelihood ratio of 2 or more voxel-wise lmer calls, testing the hypothesis that
#' the more complex model better fits the data. Note that it requires the mixed effects to have been
#' fitted with maximum likelihood, and not restricted maximum likelihood; in other words, if you want
#' to use these log likelihood tests, make sure to specify REML=FALSE in mincLmer.
#'
#' @param ... Two or more mincLmer objects
#' @return the voxel wise log likelihood test. Will have a number of columns corresponding to the
#' number of inputs -1. Note that it resorts the inputs from lowest to highest degrees of freedom
#'
#' @seealso \code{\link{lmer}} and \code{\link{mincLmer}} for description of lmer and mincLmer.
#' \code{\link{mincFDR}} for using the False Discovery Rate to correct for multiple comparisons,
#' and \code{\link{mincWriteVolume}} for outputting the values to MINC files.
#' @examples
#' \dontrun{
#' m1 <- mincLmer(filenames ~ age + sex + (age|id), data=gf, mask="mask.mnc", REML=F)
#' m2 <- mincLmer(filenames ~ age + I(age^2) + sex + (age|id), 
#'                data=gf, mask="mask.mnc", REML=F)
#' m3 <- mincLmer(filenames ~ age + I(age^2) + I(age^3) + sex + (age|id), 
#'                data=gf, mask="mask.mnc", REML=F)
#' llr <- mincLogLikRatio(m1, m2, m3)
#' mincFDR(llr)
#' mincWriteVolume(llr, "m2vsm3.mnc", "m3")
#' }
#' @export
mincLogLikRatio <- function(...) {
  dots <- list(...)
  
  # get the names of the actual objects passed it; used for naming output columns
  dotslist <- substitute(list(...))[-1];
  inputnames <- sapply(dotslist, deparse) 
  
  # test for REML vs ML, exit if REML. 
  for (i in 1:length(dots)) {
    REML <- attr(dots[[i]], "REML")
    if (is.null(REML)) {
      stop("all arguments must be the outputs of mincLmer")
    }
    else if (REML == TRUE) {
      stop("Log likelihood ratio tests only work reliably if fitted with maximum likelihood, but not if fitted with restricted maximum likelihood. Rerun your model with REML=FALSE")
    }
  }
  
  # sort the degrees of freedom of each of the models from lowest to highest
  df <- vector(length=length(dots))
  for (i in 1:length(dots)) {
    df[i] <- attr(dots[[i]], "logLikDF")
  }
  dfs <- sort(df, index.return=T)
  # create the output matrix - number of columns equal to number of objects passed in minus 1
  logLikMatrix <- matrix(nrow=nrow(dots[[1]]), ncol=length(dots))
  for (i in 1:length(dots)) {
    logLikMatrix[,i] <- dots[[dfs$ix[i]]][,"logLik"]
  }
  
  # compute the log likelihood ratio test
  flogLikRatio <- function(x) { 2 * pmax(0, diff(x)) }
  # apply at every voxel
  # erm - apply is slow as a dog here ... replace with manual rolled function
  #out <- t(apply(logLikMatrix, 1, flogLikRatio))
  out <- matrix(nrow=nrow(dots[[1]]), ncol=length(dots)-1)
  outnames <- vector(length=length(dots)-1)
  for (i in 2:length(dots)) {
    out[, i-1] <- 2 * abs(logLikMatrix[, i] - logLikMatrix[, i-1])
    outnames[i-1]  <- inputnames[dfs$ix[i]]
  }
  
  # set attributes and class types
  attr(out, "likeVolume") <- attr(dots[[1]], "likeVolume")
  attr(out, "stat-type") <- rep("chisq", ncol(out))
  attr(out, "df") <- diff(dfs$x)
  attr(out, "mask") <- attr(dots[[1]], "mask")
  
  # keep the mincLmerList for every object
  mincLmerLists <- list()
  for (i in 1:length(dots)) {
    mincLmerLists[[i]] <- attr(dots[[dfs$ix[i]]], "mincLmerList")
  }
  attr(out, "mincLmerLists") <- mincLmerLists
  if (length(dots) == 2) {
    class(out) <- c("mincLogLikRatio", "mincSingleDim", "numeric")
  }
  else {
    class(out) <- c("mincLogLikRatio", "mincMultiDim", "matrix")
  }
  colnames(out) <- outnames
  return(out)
}

#' computes parametric bootstrap on mincLogLikRatio output
#'
#' The Log Likelihood Ratio tests closely approximates a Chi-squared
#' distribution when the number of groups (i.e. individual subjects in a
#' longitudinal study) is large (>50), but can be anticonservative when
#' small. A parametric bootstrap test, in which data is randomly simulated from
#' the null model and then fit with both models, can give the correct p-value.
#' Here we compute the parametric boostrap on a small number of randomly chosen
#' voxels to get a sense of biased the estimated p-values from the log likelihood
#' ratio test really were.
#'
#' @param logLikOutput the output from mincLogLikRatio
#' @param selection the algorithm for randomly chosing voxels. Only "random" works for now.
#' @param nsims the number of simulations to run per voxel
#' @param nvoxels the number of voxels to run the parametric bootstrap on
#' @return a matrix containing the chi-square p-values and the bootstrapped p-values
#' @export
mincLogLikRatioParametricBootstrap <- function(logLikOutput, selection="random",
                                               nsims=500, nvoxels=50) {
  mincLmerLists <- attr(logLikOutput, "mincLmerLists")
  mask <- attr(logLikOutput, "mask")
  if (length(mincLmerLists) != 2) {
    stop("Error: parametric bootstrap only implemented for the two model comparison case")
  }
  if (selection == "random") {
    out <- matrix(nrow=nvoxels, ncol=2)
    simLogLik <- matrix(nrow=nsims, ncol=2)
    simLogLikRatio <- numeric(nvoxels)
    voxelMatrix <- matrix(nrow=nsims, ncol=nrow(attr(logLikOutput, "mincLmerLists")[[1]][[1]]$X))
    voxels <- mincSelectRandomVoxels(mask, nvoxels, convert=F)
    #cat(voxels)
    for (i in 1:nvoxels) {
      # refit the null model first since we'll need the merMod object for simulations
      mincLmerList <- mincLmerLists[[1]]
      voxel <- mincGetVoxel(mincLmerList[[1]]$fr[,1], mincVectorToVoxelCoordinates(mask, voxels[i]))
      mmod <- mincLmerOptimize(voxel, mincLmerList)
      for (j in 1:nsims) {
        # create the simulated data from the null model
        voxelMatrix[j,] <- unlist(simulate(mmod))
        # compute the log likelihood for the null model
        simLogLik[j,1] <- logLik(mincLmerOptimize(voxelMatrix[j,], mincLmerList))
      }
      # do it all again for the alternate model (happens in separate loop since
      # mincLmerOptimize relies on the global variable mincLmerList)
      mincLmerList <- mincLmerLists[[2]]
      for (j in 1:nsims) {
        simLogLik[j,2] <- logLik(mincLmerOptimize(voxelMatrix[j,], mincLmerList))
      }
      # compute the normally estimated chisq p value
      out[i,1] <- pchisq(logLikOutput[voxels[i]], attr(logLikOutput, "df"), 
                         lower.tail = FALSE)
      # compute the parametric log likelihood ratio
      simLogLikRatio <- 2 * abs(simLogLik[,1] - simLogLik[,2])
      # compute the parametric bootstrap p value
      out[i,2] <- mean( simLogLikRatio >= logLikOutput[voxels[i]] )
      colnames(out) <- c("chisq", "parametricBootstrap")
    }
  }
  else {
    stop("Error: unknown voxel selection mechanism")
  }
  # create a linear model of the relation between the chi square assumption and
  # the parametric bootstrap (note the lack of intercept - when p is exactly 0
  # it should be 0 in both cases
  lmodel <- lm(parametricBootstrap ~ chisq -1, data=data.frame(out))
  # make the parametric bootstrap estimates an attribute of the logLik output
  attr(logLikOutput, "parametricBootstrap") <- out
  # make the model estimate an attribute as well
  attr(logLikOutput, "parametricBootstrapModel") <- lmodel
  return(logLikOutput)
}
