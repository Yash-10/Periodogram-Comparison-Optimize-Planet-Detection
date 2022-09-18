program arbls
  implicit none

  variables1 = 1
  variables2 = 2
  variables2

contains
!!!
  subroutine eebls(n,t,x,u,v,nf,fmin,df,nb,qmi,qma,
    &p,bper,bpow,depth,qtran,in1,in2)
!!!
!!!_---------------------------------------------------------------------
!!!    >>>>>>>>>>>> This routine computes BLS spectrum <<<<<<<<<<<<<<
!!!
!!!        [ see Kovacs, Zucker & Mazeh 2002, A&A, Vol. 391, 369 ]
!!!
!!!    This is the slightly modified version of the original BLS routine 
!!!    by considering Edge Effect (EE) as suggested by 
!!!    Peter R. McCullough [ pmcc@stsci.edu ].
!!!
!!!    This modification was motivated by considering the cases when 
!!!    the low state (the transit event) happened to be devided between 
!!!    the first and last bins. In these rare cases the original BLS 
!!!    yields lower detection efficiency because of the lower number of 
!!!    data points in the bin(s) covering the low state. 
!!!
!!!    For further comments/tests see  www.konkoly.hu/staff/kovacs.html
!!!----------------------------------------------------------------------
!!!
!!!    Input parameters:
!!!    ~~~~~~~~~~~~~~~~~
!!!
!!!    n    = number of data points
!!!    t    = array {t(i)}, containing the time values of the time series
!!!    x    = array {x(i)}, containing the data values of the time series
!!!    u    = temporal/work/dummy array, must be dimensioned in the 
!!!           calling program in the same way as  {t(i)}
!!!    v    = the same as  {u(i)}
!!!    nf   = number of frequency points in which the spectrum is computed
!!!    fmin = minimum frequency (MUST be > 0)
!!!    df   = frequency step
!!!    nb   = number of bins in the folded time series at any test period       
!!!    qmi  = minimum fractional transit length to be tested
!!!    qma  = maximum fractional transit length to be tested
!!!
!!!    Output parameters:
!!!    ~~~~~~~~~~~~~~~~~~
!!!
!!!    p    = array {p(i)}, containing the values of the BLS spectrum
!!!           at the i-th frequency value -- the frequency values are 
!!!           computed as  f = fmin + (i-1)*df
!!!    bper = period at the highest peak in the frequency spectrum
!!!    bpow = value of {p(i)} at the highest peak
!!!    depth= depth of the transit at   *bper*
!!!    qtran= fractional transit length  [ T_transit/bper ]
!!!    in1  = bin index at the start of the transit [ 0 < in1 < nb+1 ]
!!!    in2  = bin index at the end   of the transit [ 0 < in2 < nb+1 ]
!!!
!!!
!!!    Remarks:
!!!    ~~~~~~~~ 
!!!
!!!    -- *fmin* MUST be greater than  *1/total time span* 
!!!    -- *nb*   MUST be lower than  *nbmax* 
!!!    -- Dimensions of arrays {y(i)} and {ibi(i)} MUST be greater than 
!!!       or equal to  *nbmax*. 
!!!    -- The lowest number of points allowed in a single bin is equal 
!!!       to   MAX(minbin,qmi*N),  where   *qmi*  is the minimum transit 
!!!       length/trial period,   *N*  is the total number of data points,  
!!!       *minbin*  is the preset minimum number of the data points per 
!!!       bin.
!!!    
!!!========================================================================
    !
    implicit real*8 (a-h,o-z)
    !
    dimension t(*),x(*),u(*),v(*),p(*)
    dimension y(2000),ibi(2000)
    !
    minbin = 5
    nbmax  = 2000
    if(nb.gt.nbmax) write(*,*) ' NB > NBMAX !!'
    if(nb.gt.nbmax) stop
    tot=t(n)-t(1)
    if(fmin.lt.1.0d0/tot) write(*,*) ' fmin < 1/T !!'
    if(fmin.lt.1.0d0/tot) stop
!!!------------------------------------------------------------------------

    rn=dfloat(n)
    kmi=idint(qmi*dfloat(nb))
    if(kmi.lt.1) kmi=1
    kma=idint(qma*dfloat(nb))+1
    kkmi=idint(rn*qmi)
    if(kkmi.lt.minbin) kkmi=minbin
    bpow=0.0d0
    !
!!!    The following variables are defined for the extension 
!!!    of arrays  ibi()  and  y()  [ see below ]
    !
    nb1   = nb+1
    nbkma = nb+kma
    !
!!!=================================
!!!    Set temporal time series
!!!=================================
    !
    s=0.0d0
    t1=t(1)
    do i=1,n
       u(i)=t(i)-t1
       s=s+x(i)
    end do
    s=s/rn
    do i=1,n
       v(i)=x(i)-s
    end do
    !
!!!******************************
!!!    Start period search     *
!!!******************************
    !
    do 100 jf=1,nf
       f0=fmin+df*dfloat(jf-1)
       p0=1.0d0/f0
       !
!!!======================================================
!!!    Compute folded time series with  *p0*  period
!!!======================================================
       !
       do j=1,nb
          y(j) = 0.0d0
          ibi(j) = 0
       end do
       !
       do  i=1,n  
          ph     = u(i)*f0
          ph     = ph-idint(ph)
          j      = 1 + idint(nb*ph)
          ibi(j) = ibi(j) + 1
          y(j) =   y(j) + v(i)
       end do
       !
!!!-----------------------------------------------
!!!    Extend the arrays  ibi()  and  y() beyond  
!!!    nb   by  wrapping
       !
       do  j=nb1,nbkma
          jnb    = j-nb
          ibi(j) = ibi(jnb)
          y(j) =   y(jnb)
       end do
       !-----------------------------------------------   
       !
!!!===============================================
!!!    Compute BLS statistics for this period
!!!===============================================
       !
       power=0.0d0
       !
       do i=1,nb
          s     = 0.0d0
          k     = 0
          kk    = 0
          nb2   = i+kma
          do  j=i,nb2
             k     = k+1
             kk    = kk+ibi(j)
             s     = s+y(j)
             if(k.lt.kmi) go to 2
             if(kk.lt.kkmi) go to 2
             rn1   = dfloat(kk)
             pow   = s*s/(rn1*(rn-rn1))
             if(pow.lt.power) go to 2
             power = pow
             jn1   = i
             jn2   = j
             rn3   = rn1
             s3    = s
          end do
       end do
       !
       power = dsqrt(power)
       p(jf) = power
       !
       if(power.lt.bpow) go to 100
       bpow  =  power
       in1   =  jn1
       in2   =  jn2
       qtran =  rn3/rn
       depth = -s3*rn/(rn3*(rn-rn3))
       bper  =  p0
       !
    end do
    !
!!! Edge correction of transit end index
    !
    if(in2.gt.nb) in2 = in2-nb     
    !
  end subroutine eebls
                   
end program arbls