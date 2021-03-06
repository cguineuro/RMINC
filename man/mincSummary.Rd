% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/minc_voxel_statistics.R
\name{mincSummary}
\alias{mincSummary}
\alias{mincMean}
\alias{mincVar}
\alias{mincSum}
\alias{mincSd}
\alias{mincCorrelation}
\title{Minc Voxel Summary Functions}
\usage{
mincSummary(filenames, grouping = NULL, mask = NULL, method = "mean",
  maskval = NULL)

mincMean(filenames, grouping = NULL, mask = NULL, maskval = NULL)

mincVar(filenames, grouping = NULL, mask = NULL, maskval = NULL)

mincSum(filenames, grouping = NULL, mask = NULL, maskval = NULL)

mincSd(filenames, grouping = NULL, mask = NULL, maskval = NULL)

mincCorrelation(filenames, grouping, mask = NULL, maskval = NULL)
}
\arguments{
\item{filenames}{Filenames of the MINC volumes across which to create the
descriptive statistic.}

\item{grouping}{Optional grouping - contains same number of elements as
filenames; the results will then have the descriptive
statistic computed separately for each group, or in the case of method = "correlation"
this is the variable to correlate against.}

\item{mask}{A mask specifying which voxels are to be included in the
summary.}

\item{method}{the type of summarys statistic to calculate for each voxel}

\item{maskval}{the value in the mask used to select unmasked voxels, 
defaults to any positive intensity from 1-99999999 internally expanded to
.5 - 99999999.5. If a number is specified voxels with intensities 
within 0.5 of the chosen value are considered selected.}
}
\value{
The output will be a single vector containing as many
         elements as there are voxels in the input files. If a
         grouping factor was specified then the output will be a
         matrix consisiting of as many rows as there were voxels in
         the files, and as many columns as there were groups.
}
\description{
Compute the mean, standard deviation, sum, or variance at every voxel across a
a set of MINC volumes.
An optional grouping variable will split the computation by group
rather than performing it across all volumes as is the default.
}
\section{Functions}{
\itemize{
\item \code{mincMean}: mean

\item \code{mincVar}: Variance

\item \code{mincSum}: Sum

\item \code{mincSd}: Standard Deviation

\item \code{mincCorrelation}: Correlation
}}

\examples{
\dontrun{
getRMINCTestData() 
gf <- read.csv("/tmp/rminctestdata/minc_summary_test_data.csv") 
mm <- mincMean(gf$jacobians_0.2) 
ms <- mincSd(gf$jacobians_0.2)
mv <- mincVar(gf$jacobians_0.2,gf$Strain) 
ms2 <- mincSum(gf$jacobians_0.2,gf$Strain)
}
}
