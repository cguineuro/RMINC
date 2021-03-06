% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/minc_interface.R
\name{as.minc}
\alias{as.minc}
\title{Coerce to RMINC object}
\usage{
as.minc(x)
}
\arguments{
\item{x}{the object to coerce}
}
\value{
if x is a known minc type return it, if it is a list, attempt
to reduce it toa minc object via \link{simplify2minc}, otherwise check
if the object has columns, if so reclass it as \code{mincMultiDim} otherwise
reclass it as a \code{mincSingleDim}
}
\description{
Coerce a relatively simple object to an RMINC known object
(currently \code{mincList}, \code{mincSingleDim}, \code{mincMultiDim})
}
