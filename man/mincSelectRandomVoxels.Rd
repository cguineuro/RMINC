% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/minc_interface.R
\name{mincSelectRandomVoxels}
\alias{mincSelectRandomVoxels}
\title{selects a few random indices from a volume}
\usage{
mincSelectRandomVoxels(volumeFileName, nvoxels = 50, convert = TRUE, ...)
}
\arguments{
\item{volumeFileName}{the filename for a MINC volume}

\item{nvoxels}{the number of voxels to select}

\item{convert}{whether to convert to MINC voxel space (default) or keep in index space}

\item{...}{additional arguments}
}
\value{
A vector of length \code{nvoxels} containing selected voxel indices or if convert is true
a matrix containing the x-y-z coordinates of the selected voxels.
}
\description{
Given a filename, select a few random indices using the uniform distribution
from voxels that have a value of 1 (i.e. from a mask volume)
}
