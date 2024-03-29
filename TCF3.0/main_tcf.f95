
subroutine main_tcf(ny,y,na,nper,inper,outpow,outdepth,outphase&
     &,outdur,outmad)
  use rand_tools
  use tcf_tools
  use m_median
  implicit none
  integer, intent(in) :: ny, nper
  double precision, intent(in), dimension(ny) :: y
  integer, intent(in), dimension(ny) :: na
  double precision, intent(in), dimension(nper) :: inper
  double precision, intent(out), dimension(nper) :: outpow,outdepth&
       &,outphase,outdur,outmad
  !!
  double precision, dimension(ny) :: cy
  double precision mad
 
!!! Initialize random number generator
  call init_random_seed()
!!!!! Center y 
!!$  cy = y - sum(y, MASK = na==0)/dble(count(na==0))
!!$  cy = y
!!!!! Center y to 0 median
  cy = y - median(pack(y, MASK = na==0))
  mad = median(abs(pack(cy, MASK = na==0)))
  cy = cy/mad

  call tcf(cy,na,inper,outpow,outdepth,outphase,outdur,outmad)
  
  outdepth = outdepth*mad
  outmad = outmad*mad

end subroutine main_tcf
