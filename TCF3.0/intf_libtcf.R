#### to compile shared library, run on terminal:
## ' R CMD SHLIB planetfilter... '

#### this file can be sourced via 'source(pfilt_interface.R)' in an R session

dyn.load("/kaggle/working/arps/TCF3.0/a.out")

tcf <- function(y,     ## time series vector
##                per.range = c(2,length(y)/2),
##                nper = length(y),
		  p.try,
                print.output = TRUE
               ){
  na.list <- is.na(y)
  y[na.list] <- 0 #ifelse(na.list,-999,data.vals)
  na.list <- ifelse(na.list,1,0)
  ny <- length(y)
  ## sp <- rep(0,splt*(map-mip)+1)
  ## sp <- rep(0,splt*(map-mip))
  ## ntransits <- tot.pts/(mip:(map-1))
##  per.range <- sort(per.range)
  ## test.per <- 1/seq(1/per.range[1],1/per.range[2],length.out=nper)
  ## test.per <- seq(per.range[1],per.range[2],length.out=nper)
  test.per <- p.try
  dummy.vec <- rep(0,length(test.per))
  tcf.F <- .Fortran("main_tcf",
                 ny = as.integer(ny),
                 y = as.numeric(y),
                 na = as.integer(na.list),
                 nper = as.integer(length(test.per)),
                 inper = as.numeric(test.per),
                 outpow = as.numeric(dummy.vec),
                 outdepth = as.numeric(dummy.vec),
                 outphase = as.numeric(dummy.vec),
                 outdur = as.numeric(dummy.vec),
                 outmad = as.numeric(dummy.vec)
                  )
  if(print.output == T){
    powmax.loc = which.max(tcf.F$outpow)
    print(c("Period = ",tcf.F$inper[powmax.loc])) #(per.temp-1)/splt + mip))
    print(c("Power = ",tcf.F$outpow[powmax.loc]))
    print(c("Depth = ",tcf.F$outdepth[powmax.loc]))
    print(c("Duration = ",tcf.F$outdur[powmax.loc]))
    print(c("Phase = ",tcf.F$outphase[powmax.loc]))
  }
  return(tcf.F)
}
