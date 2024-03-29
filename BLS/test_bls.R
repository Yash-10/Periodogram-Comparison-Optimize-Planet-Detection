
#### to compile shared library, run on terminal:
## ' R CMD SHLIB eebls.f '

#### this file can be sourced via 'source(bls.R)' in an R session

dyn.load("/home/oem/arps/arps/BLS/a.out")
bls <- function(data.vals,     ## vector with signal
                data.times,    ## vector with times
                bls.plot = TRUE,   ## plot periodogram
                nbins = round(length(data.vals)*0.1),  ## BLS bin number
                per.min = data.times[3]-data.times[1], ## min period to test
                per.max = data.times[length(data.times)]-data.times[1], ##max period
                nper = length(data.times)*10, ##numper of period values to test
                q.min = 0.01, ## min duration/period fraction
                q.max = 0.15,  ## max duration/period fraction
                print.output = TRUE
                ){
  tot.pts <- length(data.vals)
  freq.min <- 1/per.max
  freq.max <- 1/per.min
  nfreq <- nper
  freq.step <- (freq.max - freq.min)/nfreq
  fBLS <- .Fortran("eebls",
                   n = as.integer(tot.pts),
                   t = as.numeric(data.times),
                   x = as.numeric(data.vals),
                   u = as.numeric(1:tot.pts),
                   v = as.numeric(1:tot.pts),
                   nf = as.integer(nfreq),
                   fmin = as.numeric(freq.min),
                   df = as.numeric(freq.step),
                   nb = as.integer(nbins),
                   qmi = as.numeric(q.min),
                   qma = as.numeric(q.max),
                   ##
                   p = as.numeric(1:nfreq),
                   bper = as.numeric(1),
                   bpow = as.numeric(1),
                   depth = as.numeric(1),
                   qtran = as.numeric(1),
                   in1 = as.integer(1),
                   in2 = as.integer(1)
                   )
  f = seq(freq.min,by=freq.step,length.out=nfreq)
  per = 1/f
  if(bls.plot==TRUE) {
    plot(per,fBLS$p,type="l",xlab = "Period",ylab = "Power")
  }
  bls.vals <- list(fBLS$p,fBLS$bper,fBLS$bpow,fBLS$depth,fBLS$qtran,fBLS$qtran*fBLS$bper,per)
  names(bls.vals) <- c("spec","per","maxpow","depth","qtran","dur", "periodsTested")
  if (print.output) {
    print(noquote(paste("Peak Power =",sprintf("%.6f",fBLS$bpow))))
    print(noquote(paste("Period =",sprintf("%.3f",fBLS$bper))))
    print(noquote(paste("Depth =",sprintf("%.6f",fBLS$depth))))
    print(noquote(paste("Duration =",sprintf("%.3f",fBLS$qtran*fBLS$bper))))
  }
  return(bls.vals)
}
