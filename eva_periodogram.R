#################################################
############## IMPORTANT REFERENCES #############
# http://quantdevel.com/BootstrappingTimeSeriesData/BootstrappingTimeSeriesData.pdf (About bootstrapping in time-series data).
# http://www.ccpo.odu.edu/~klinck/Reprints/PDF/omeyHUB2009.pdf (suggested by Suveges, 2014).
# See about aliasing at the end of this page, for example: https://docs.gammapy.org/0.8/time/period.html and this also: https://hea-www.harvard.edu/~swolk/thesis/period/node5.html
# See discussion on period/frequency spacing considerations for BLS: https://johnh2o2.github.io/cuvarbase/bls.html#period-spacing-considerations
# Mathematical description of the Anderson-Darling test: https://bookdown.org/egarpor/NP-UC3M/nptests-dist.html

########### Resources for extreme value statistics ##########
# (1) http://personal.cityu.edu.hk/xizhou/first-draft-report.pdf
# (2) Playlist on Extreme Value Statistics: https://youtube.com/playlist?list=PLh35GyCXlQaTJtTq4OQGzMblwEcVIWW9n
# https://www.lmd.ens.fr/E2C2/class/naveauRomaniaE2C207.pdf

#############################################################
# Good set of papers: https://arxiv.org/pdf/1712.00734.pdf

#################################################

library('extRemes')
library('boot')
# library('GoFKernel')
library('cobs')
source('BLS/bls.R')
source('TCF3.0/intf_libtcf.R')
source('test_periodograms.R')
library('goftest')  # install.packages("goftest")
library('gbutils')  # https://search.r-project.org/CRAN/refmans/gbutils/html/cdf2quantile.html

statFunc <- function(a) { return (a) }

fredivideFreqGrid <- function(freqGrid, L, K) {
    # # Divide the frequency into L bins, each with K datapoints.
    # ## From https://stackoverflow.com/questions/57889573/how-to-randomly-divide-interval-into-non-overlapping-spaced-bins-of-equal-lengt
    # intervalLength <- length(freqGrid)
    # nBins <- L
    # binWidth <- K
    # binMinDistance <- 1
    # spaceToDistribute <- intervalLength - (nBins * binWidth + (nBins - 1) * binMinDistance)
    # distances <- diff(floor(c(0, sort(runif(nBins))) * spaceToDistribute))
    # startOfBin <- cumsum(distances) + (0:(nBins-1)) * 101
    # KLinds <- data.frame(bin = 1:nBins, startOfBin = startOfBin, endOfBin = startOfBin + binWidth - 1)

    # stopifnot(exprs={  # Check if the no. of frequencies in a bin is in fact equal to the desired number.
    #     length(freqGrid[KLinds[1, 2]:KLinds[1, 3]]) == binWidth
    # })

    # KLfreqs <- c()
    # for (i in 1:nrow(KLinds)) {
    #     Kfreqs <- freqGrid[KLinds[i, 2]:KLinds[i, 3]]
    #     KLfreqs <- append(KLfreqs, Kfreqs)
    # }
    # return (KLfreqs);

    # TODO: Need to verify this works as expected for large oversampling factors. I think that the hackery below might still yield errors for larger ofac values than 2.
    if ((K %% 2) == 0) {
        safeDist <- 1 + K/2  # 1 is added just to be more safe at the edges of the frequency grid. This is just a hackery.
    }
    else {
        safeDist <- 1 + (K-1)/2  # 1 is added just to be more safe at the edges of the frequency grid. This is just a hackery.
    }
    endIndex <- length(freqGrid) - safeDist
    freqConsider <- freqGrid[safeDist:endIndex]
    LcentralFreqs <- sample(freqConsider, L, replace=FALSE, prob=rep(1/length(freqConsider), length(freqConsider)))  # replace=FALSE to prevent sampling the same frequency again. According to Suveges, each of the L central freqeuencies is selected with equal probability, so we pass an equal probability vector.
    KLfreqs <- c()
    for (i in 1:length(LcentralFreqs)) {
        index <- match(LcentralFreqs[i], freqGrid)
        if ((K %% 2) == 0) {
            k_ <- as.integer(K/2)
            lowerIndx <- index-k_
            upperIndx <- index+(K-k_-1)
            KLfreqs <- append(KLfreqs, freqGrid[lowerIndx:upperIndx])
        }
        else {
            kminusonehalf <- as.integer((K-1) / 2)
            lowerIndx <- index-kminusonehalf
            upperIndx <- index+kminusonehalf
            KLfreqs <- append(KLfreqs, freqGrid[lowerIndx:upperIndx])
        }
    }
    return (KLfreqs);
}

calculateReturnLevel <- function(
    fap,   # Requested fap.
    # Parameters of the fitted GEV model.
    location,
    scale,
    shape,
    K, L,  # These are parameters used for bootstrapping time series.
    n  # Length of the full frequency grid.
) {
    returnLevel <- qevd(
        1 - ((fap * K * L) / n),
        loc=location, scale=scale, shape=shape, type="GEV"
    )
    return (returnLevel);
}

calculateFAP <- function(
    location,
    scale,
    shape,
    K, L,
    n,
    periodogramMaxima
) {
    calculatedFAP <- (n / (K * L)) * (1 - pevd(periodogramMaxima, loc=location, scale=scale, shape=shape, type="GEV"))
    return (calculatedFAP);
}

evd <- function(
    period,
    depth,
    duration,
    L=500,  # No. of distinct frequency bins.
    R=1000,  # No. of bootstrap resamples of the original time series.
    noiseType=1,  # Noise model present in y. Either 1 (white gaussian noise) or 2 (autoregressive noise). Resampling technique is dependent on this, see http://quantdevel.com/BootstrappingTimeSeriesData/BootstrappingTimeSeriesData.pdf
    # Note: noiseType is not used for adding noise to series, but instead used for deciding the way of resampling.
    algo="BLS",
    ntransits=10,
    plot = TRUE,
    ofac=2,  # ofac is also called as "samples per peak" sometimes.
    useOptimalFreqSampling = FALSE,  # If want to use the optimal frequency sampling from Ofir, 2014: delta_freq = q / (s * os), where s is whole time series duration, os is oversampling factor and q is the duty cycle (time in single transit / total time series duration).
    alpha=0.05  # Significance level for hypothesis testing on the GEV fit on periodogram maxima. TODO: How to choose a significance level beforehand - any heuristics to follow?
) {

    K <- ofac  # No. of distinct frequencies in a frequency bin.  # Note that in Suveges, 2014, K = 16 is used and K is called as the oversampling factor. So we also do that.
    # In short, L allows capturing long-range dependence while K prevents spectral leakage -- from Suveges.
    # TODO: We need to do some test by varying L and R to see which works better for each case?

    # Generate light curve using the parameters.
    yt <- getLightCurve(period, depth, duration, noiseType=noiseType, ntransits=ntransits)
    y <- unlist(yt[1])
    t <- unlist(yt[2])

    # Special case (TCF fails if absolutely no noise -- so add a very small amount of noise just to prevent any errors).
    if (noiseType == 0 && algo == "TCF") {
        y <- y + 10^-10 * rnorm(length(y))
    }

    # (1) Bootstrap the time series.
    # The reason why we first bootstrap the time series and then take block maxima rather than simply bootstrapping block maxima of original series is mentioned in first paragraph in https://personal.eur.nl/zhou/Research/WP/bootstrap_revision.pdf
    # Non-parametric bootstrap with replacement of blocks.
    # if (noiseType == 1) {
    #     bootTS <- replicate(R, replicate(length(y), sample(y, 1, replace=TRUE)))
    #     bootTS <- aperm(bootTS)  # This just permutes the dimension of bootTS - rows become columns and columns become rows - just done for easier indexing further in the code.
    #     # At this point, bootTS will be of shape (R, length(y)).
    # }
    # Note that bootstrapping, by definition, is resampling "with replacement": https://en.wikipedia.org/wiki/Bootstrapping_(statistics)
    # We use block resampling irrespective of the noise (i.e. block resampling even if noise is uncorrelated in white Gaussian noise), because the underlying time-series is in the form of repeated box-like shapes, and we would like to preserve that in order to look more like the original time-series.
    # Note: A general option for time-series with independent data is to use: random, uniform bootstrapping, but that can distort the repeating box-like shapes in the time series.
    # bootTS <- tsboot(ts(y), statistic=statFunc, R=R, sim="fixed", l=period*24, n.sim=length(y))$t  # block resampling with fixed block lengths
    # Here, the block length is chosen to be slightly larger than the period (so that each block atleast contains a period -- a heuristic).
    # This answer: https://stats.stackexchange.com/a/317724 seems to say that block resampling resamples blocks with replacement.
    # Also note that Suveges says that the marginal distribution of each of the bootstrapped resample time series must approximately be the same as the original time series.

    # bootTS <- replicate(R, replicate(length(y), sample(y, 1, replace=TRUE)))
    bootTS <- replicate(R, sample(y, length(y), replace=TRUE))
    bootTS <- aperm(bootTS)  # This just permutes the dimension of bootTS - rows become columns and columns become rows - just done for easier indexing further in the code.

    stopifnot(exprs={
        dim(bootTS) == c(R, length(y))
    })

    ### Create a frequency grid.
    ################## Ofir, 2014 - optimal frequency sampling - notes #################
    # (1) "It is now easy to see that the frequency resolution ∆f is no longer constant - it depends on f itself due to the physics of the problem."
    # (2) Section 3.2 also says that by using a very fine frequency grid (suitable for long-period signals), we (a) increase computation time a lot, and (b) it will be too sensitive to noise and less to actual real signals.

    # In this code, there is also an option to use Ofir, 2014's suggestion to use the optimal frequency sampling rather than the default uniform frequency sampling.
    # Note that the fact that we uniformly sample in "frequency" rather than "period" is itself a good choice: see last para in sec 7.1 in https://iopscience.iop.org/article/10.3847/1538-4365/aab766/pdf
    # Note that while using min frequency as zero is often not a problem (does not add suprious peaks - as described in 7.1 in https://iopscience.iop.org/article/10.3847/1538-4365/aab766/pdf), here we start with min_freq = 1 / (duration of time series).
    # One motivation for oversampling (from https://iopscience.iop.org/article/10.3847/1538-4365/aab766/pdf): "...it is important to choose grid spacings smaller than the expected widths of the periodogram peaks...To ensure that our grid sufficiently samples each peak, it is prudent to oversample by some factor—say, n0 samples per peak--and use a grid of size 1 / (n0 * T)"
    # The above paper also says that n0 = 5 to 10 is common.
    perMin <- t[3] - t[1]
    perMax <- t[length(t)] - t[1]
    freqMin <- 1 / perMax
    freqMax <- 1 / perMin
    # nfreq <- length(t) * 10

    if (useOptimalFreqSampling) {
        if (algo == "BLS") {
            q = duration  # single transit duration / light curve duration.
        }
        else if (algo == "TCF") {  # TODO: This actually yields a very bad GEV fit - so something is wrong in calculating the duty cycle for TCF.
            # Duty cycle for TCF taken from Caceres, 2019 methodology paper: https://iopscience.iop.org/article/10.3847/1538-3881/ab26b8
            q = 1 / (period * 24)
        }
        s = length(t)
        freqStep = q / (s * ofac)
    }
    else {
        # Note: When we oversample, we are essentially imposing no constraints on the frequencies to be tested - that is helpful in general: see https://arxiv.org/pdf/1712.00734.pdf
        # Note that too much oversampling can lead to artifacts. These artifacts can be wrongly interpreted as a true periodic component in the periodogram.
        freqStep <- (freqMax - freqMin) / (nfreq * ofac)  # Oversampled by a factor, `ofac`.
    }

    freqGrid <- seq(from = freqMin, to = freqMax, by = freqStep)  # Goes from ~0.001 to 0.5 (NOTE: Since delta_t = 1, fmax must be <= Nyquist frequency = 1/(2*delta_t) = 0.5 -- from Suveges, 2014).
    print(sprintf("No. of frequencies in grid: %f", length(freqGrid)))

    stopifnot(exprs={
        all(freqGrid <= 0.5)  # No frequency must be greater than the Nyquist frequency.
        length(freqGrid) >= K * L  # K*L is ideally going to be less than N, otherwise the bootstrap has no benefit in terms of compuation time.
    })

    # (2) Max of each partial periodogram
    # Note that from Suveges paper, the reason for doing block maxima is: "The principal goal is to decrease the computational load due to a bootstrap. At the same time, the reduced frequency set should reflect the fundamental characteristics of a full periodogram: ..."
    # TODO: Should we use standardization/normalization somewhere? See astropy _statistics module under LombScargle to know at which step to normalize -- should we normalize these bootstrap periodograms or only the final full periodogram.
    maxima_R <- c()
    for (j in 1:R) {
        KLfreqs <- fredivideFreqGrid(freqGrid, L, K)
        stopifnot(exprs={
            length(KLfreqs) == K * L
        })

        # TODO: Decide whether to use standardized or normal periodogram only for the partial ones?
        if (algo == "BLS") {
            partialPeriodogram <- bls(bootTS[j,], t, per.min=min(1/KLfreqs), per.max=max(1/KLfreqs), nper=K*L, bls.plot = FALSE)$spec
            # partialPeriodogram <- unlist(standardPeriodogram(bootTS[j,], t, perMin=min(1/freqs), perMax=max(1/freqs), nper=K, plot = FALSE, noiseType=noiseType)[1])
        }
        else {
            # For TCF, select K frequencies from freqs.
            freqsTCF <- seq(min(KLfreqs), max(KLfreqs), length.out=K*L)
            partialPeriodogram <- tcf(diff(bootTS[j,]), p.try = 1 / freqsTCF, print.output = FALSE)$outpow
            # partialPeriodogram <- unlist(standardPeriodogram(bootTS[j,], t, perMin=min(1/freqs), perMax=max(1/freqs), nper=K, plot = FALSE, noiseType=noiseType, algo="TCF")[1])
        }

        # Note: If we use oversampling, then while it increases the flexibility to choose frequencies in the frequency grid, it also has important issues as noted in https://academic.oup.com/mnras/article/388/4/1693/981666:
        # (1) "if we oversample the periodogram, the powers at the sampled frequencies are no longer independent..."
        # To solve the above problem, we decluster the partial periodograms. Even without oversampling, the peaks tend to be clustered and we need to decluster the peaks.

        # TODO: See performance with and without declustering.
        # Decluster the peaks: https://search.r-project.org/CRAN/refmans/extRemes/html/decluster.html
        # Some intution on how to choose the threshold: https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.996.914&rep=rep1&type=pdf (search for threshold - Ctrl+F - in the paper)
        # See section 5.3.2 in Coles, 2001 to see why declustering is needed: Extremes tend to cluster themselves and tend to occur in groups. Note that log-likelihood can be decomposed into a product of individual marginal distribution functions only under iid. So declustering "tries" to make them independent to prevent the violation of the iid assumption while fitting the GEV model below.
        # In short, declustering (approximately) solves the dependence issue of extremes.
        # TODO: We might not need declustering in all cases -- we can calculate the extremel index and do declustering only if index < 1...
        # Due to our way of extracting maxima of periodograms (i.e. not from whole periodogram but only from partial periodogram), maybe we do not even need declustering.
        # TODO: How to choose best threshold for declustering?
        partialPeriodogram <- decluster(partialPeriodogram, threshold = quantile(partialPeriodogram, probs=c(0.75)))
        maxima_R <- append(maxima_R, max(partialPeriodogram))
    }
    print("Done calculating maxima...")
    # print(maxima_R)

    # (3) GEV modelling of partial periodograms' maxima
    fitEVD <- fevd(maxima_R, type='GEV')
    # See https://www.dataanalysisclassroom.com/lesson60/ for discussion on the fevd function.
    print(summary(fitEVD))
    distill(fitEVD)

    ## Get the fitted GEV parameters
    location <- findpars(fitEVD)$location[1]  # In extRemes, the parameter values repeat R times (for stationary models), and all are same. So extract the first.
    scale <- findpars(fitEVD)$scale[1]
    shape <- findpars(fitEVD)$shape[1]

    print(sprintf("location: %f, scale: %f, shape: %f", location, scale, shape))

    ## Important note: It would be better to find an automatic way to judge whether we want to select a GEV model or not, instead of manually looking at the diagnostic plots. This is because we want to apply this method on several periodograms. Hence we perform the A-D test.
    # Diagnostic goodness-of-fit tests (we use the Anderson-Darling (AD) test: https://search.r-project.org/CRAN/refmans/DescTools/html/AndersonDarlingTest.html)
    # A simple reason why we use the Anderson–Darling (AD) test rather than Komogorov-Smirnov (KS) is that AD is able to detect better the situations in which F0 and F differ on the tails (that is, for extreme data), where H0: F = F0 and H1: F \neq F0.
    result <- ad.test(maxima_R, null = "pevd", loc=location, scale=scale, shape=shape, nullname = "pevd", estimated = FALSE)  # estimated = TRUE would have been fine as well since the gevd parameters (location, scale, shape) are estimated using the data itself - those three parameters are not data-agnostic. But here we use estimated = FALSE because using TRUE uses a different variant of AD test using the Braun's method which we do not want.
    print(result)
    print(sprintf("p-value for Anderson-Darling goodness-of-fit test of the periodogram maxima: %f", result$p.value))
    # TODO: Usign pgevd gives diff FAP values than using pevd??
    # Check if AD fit is good enough. If not, return a dummy fap value.
    # This check serves as a way to "automatically" find if the GEV fit is good and if it can be extrapolated to the full periodogram.
    # Suveges, 2014 suggests looking at the diagnostic plots before extrapolating to full periodogram, but that is cumbersome for large-scale simulations. Hence, this is a simple way to overcome manual fit quality inspection.
    if (result$p.value < alpha) {  # Reject null hypothesis: the maxima sample is in the favor of alternate hypothesis (that the sample comes from a different distribution than GEV).
        fap <- -999
        print("Anderson-Darling test failed while fitting GEV to the sample periodogram maxima. A dummy fap value will be returned with value -999.")
        return (fap)
    }

    # Diagnostic plots.
    if (plot) {
        # TODO: Why ci fails sometimes?
        try(plot(fitEVD))
        # plot(fitEVD, "trace")
        # return.level(fitEVD)
        # return.level(fitEVD, do.ci = TRUE)
        # ci(fitEVD, return.period = c(2, 20, 100))
        # See some description on how ci's are calculated: https://reliability.readthedocs.io/en/latest/How%20are%20the%20confidence%20intervals%20calculated.html
    }

    # (4) Extrapolation to full periodogram
    print("Extrapolating to full periodogram...")

    # Compute full periodogram (note: standardized periodogram is used).
    # TODO: Since standardized periodogram's scale has changed (due to scatter-removal), it lies at the end of gev cdf, thus always giving fap=0.000 -- fix this: either remove the scatter or do some hackery to prevent this from happening.
    if (algo == "BLS") {
        ## On standardized periodogram
        # op <- getStandardPeriodogram(period, depth, duration, noiseType=noiseType, algo=algo, ntransits=ntransits)
        # output <- unlist(op[1])
        # periodsTested <- unlist(op[2])
        # periodEstimate <- periodsTested[which.max(output)]

        # fullPeriodogramReturnLevel <- pevd(max(output), loc=location, scale=scale, shape=shape)
        # print(sprintf("FAP (standardized periodogram): %f", nfreq * (1 - fullPeriodogramReturnLevel) / (K * L)))  # This formula is from Suveges, 2014.

        ## On original periodogram
        output <- bls(y, t, bls.plot = FALSE)$spec
    }
    else {
        # op <- getStandardPeriodogram(period, depth, duration, noiseType=noiseType, algo=algo, ntransits=ntransits)
        # output <- unlist(op[1])
        # periodsTested <- unlist(op[2])
        # periodEstimate <- periodsTested[which.max(output)]

        # fullPeriodogramValue <- pevd(max(output), loc=location, scale=scale, shape=shape)
        # print(sprintf("FAP (standardized periodogram): %f", nfreq * (1 - fullPeriodogramValue) / (K * L)))  # This formula is from Suveges, 2014.

        perMin = t[3] - t[1]
        perMax = t[length(t)] - t[1]
        freqMax = 1 / perMin
        freqMin = 1 / perMax
        nfreq = length(y) * 10
        freqStep = (freqMax - freqMin) / nfreq
        f = seq(freqMin, by=freqStep, length.out=nfreq)
        periodsToTry = 1 / f
        output <- tcf(diff(y), p.try = periodsToTry, print.output = FALSE)$outpow
    }
    # Decluster the full periodogram as well.
    output <- decluster(output, threshold = quantile(output, probs=c(0.75)))

    print("Calculating return level...")
    returnLevel <- calculateReturnLevel(0.01, location, scale, shape, K, L, length(freqGrid))
    print(sprintf("Return level corresponding to FAP = %f: %f", 0.01, returnLevel))

    # For interpretation, we would like to get FAP given a return level rather than giving return level from a given FAP.
    print("Calculating FAP...")
    fap <- calculateFAP(location, scale, shape, K, L, length(freqGrid), max(output))
    print(sprintf("FAP = %.10f", fap))

    # Verify that the period corresponding to the largest peak in standardized periodogram is the same as in original periodogram.
    # stopifnot(exprs={
    #     all.equal(periodEstimate, periodsTested[which.max(output)], tolerance = sqrt(.Machine$double.eps))
    # })

    return (c(fap, summary(fitEVD)$AIC));

    ###### Interpreting what FAP is good (from Baluev: https://academic.oup.com/mnras/article/385/3/1279/1010111):
    # (1) > Given some small critical value FAP* (usually between 10−3 and 0.1), we can claim that the candidate signal is statistically
    # significant (if FAP < FAP*) or is not (if FAP > FAP*)
}

validate1_evd <- function(  # Checks whether the values in the bootstrappe resample are actually from the original time series, which is a must.
    y,
    t,
    bootTS,
    R
) {
    for (j in 1:R) {
        for (i in 1:length(y)) {
            myVec <- c(bootTS$t[j,])
            stopifnot(exprs = {
                y[i] %in% myVec  # Obviously, values in the bootstrap sample must be there in the original time series since we are sampling from it.
            })
            any(duplicated(myVec))  # Fine if observations in the bootstrap resamples series duplicates.
        }
    }
}

findbestLandR <- function(  # Finds the optimal L and R values via grid search. It uses the AIC for finding the best {L, R} pair.
    Ls,
    Rs,
    period,
    depth,
    duration,
    noiseType=1,
    algo="BLS",
    ofac=1,
    useOptimalFreqSampling = FALSE
) {
    # *** CAUTION: Do not use this code with large Ls and Rs lengths. It is only meant to compare a few L and R pairs and not for large scale tuning ***

    stopifnot(exprs={
        length(Ls) == length(Rs)
    })
    minAIC <- Inf
    bestLR <- NULL
    for (i in 1:length(Ls)) {
        result <- evd(period, depth, duration, Ls[i], Rs[i], noiseType=noiseType, algo=algo, ofac=ofac, useOptimalFreqSampling=useOptimalFreqSampling)
        aic <- result[2]
        if (aic < minAIC) {
            minAIC = aic
            bestLR <- c(Ls[i], Rs[i])
        }
    }
    return (bestLR)
}

smallestPlanetDetectableTest <- function(  # This function returns the smallest planet detectable (in terms of transit depth) using the FAP criterion.
    period,  # in days
    depths,  # in %
    duration,  # in hours
    algo="BLS",  # either BLS or TCF
    noiseType=1,  # 1 for Gaussian and 2 for autoregressive noise
    ofac=2
) {
    faps <- c()
    for (depth in depths) {
        result <- evd(period, depth, duration, algo=algo, plot=FALSE, ofac=ofac)
        fap <- result[1]
        print(sprintf("depth (ppm): %f, fap: %f", depth*1e4, fap))
        faps <- append(faps, fap)
    }

    png(filename=sprintf("%sdays_%shours.png", period, duration * period * 24))
    plot(depths*1e4, faps, xlab='Depth (ppm)', ylab='FAP', type='o', ylim=c(1e-7, 0.1))
    axis(1, at=1:length(depths), labels=depths*1e4)
    if (noiseType == 1) {
        abline(h=0.01, col='black', lty=2)  # Here 1% FAP is used. Another choice is to use FAP=0.003, which corresponds to 3-sigma criterion for Gaussian -- commonly used in astronomy.
    }
    else {
        abline(h=0.002, col='black', lty=2)  # TODO: Decide what threshold FAP to use for the autoregressive case.
    }
    dev.off()
}

# This function finds the root of the equation: FAP(depth, **params) - 0.01 = 0, i.e., given the period and duration of a planet,
# it finds the depth corresponding to the case FAP = 0.01 called the limiting_depth. So any transit with depth < limiting_depth
# is statistically insignificant using the FAP = 0.01 criterion.
depthEquation <- function(depth, period=3, duration=1/36) {
    result <- evd(period, depth, duration, ofac=1, plot = FALSE)
    return (result[1] - 0.01);
}

# This function is a high-level wrapper for `findLimitingDepth` that prints the limiting depth.
# Root solving is done using the Newton-Raphson iteration method via the `uniroot` function in R.
findLimitingDepth <- function() {
    print('Finding limiting depth corresponding to FAP = 0.01')
    print(uniroot(depthEquation, c(0.004, 3)))  # Lower and upper limits set using the range of depths typically observed in Kepler (40 ppm - 30000 ppm).
}

# This function is only for a quick verification test. One would not expect to get the exact depth where the planet starts to become insignificant.
periodDurationDepthTest <- function(
    algo="BLS",
    ofac=1
) {
    depths <- c(0.1, 0.08, 0.06, 0.04, 0.02, 0.01, 0.005)  # in %

    periodDurations <- list()
    periodDurations[[1]] <- c(2, 1/24)  # 2 days, 2 hrs
    periodDurations[[2]] <- c(3, 1/36)  # 3 days, 2 hrs
    periodDurations[[3]] <- c(4, 1/48)  # 4 days, 2 hrs
    periodDurations[[4]] <- c(5, 1/60)  # 5 days, 2 hrs

    for (periodDuration in periodDurations) {
        period <- periodDuration[1]
        duration <- periodDuration[2]
        smallestPlanetDetectableTest(period, depths, duration, algo=algo, ofac=ofac)
    }
}
################# Questions not yet understood by me ##################
# (1) What is "high quantiles of a distribution"? See online where mainly talk about heavy-tailed distributions..