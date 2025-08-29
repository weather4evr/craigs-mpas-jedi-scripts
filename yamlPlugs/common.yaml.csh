#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
# reduce obs space for regional applications
_regional reduce obs space: &regionalReduceObsSpace
  filter: Domain Check
  where:
    - variable:
        name: MetaData/latitude
      minvalue: 15.0 #-90.0
      maxvalue: 30.0 #90.0
    - variable:
        name: MetaData/longitude
      minvalue: 110.0 #-180.0
      maxvalue: 130.0 #180.0
  action:
    name: reduce obs space

_global reduce obs space: &globalReduceObsSpace
  _blank: null

_reduce obs space: &reduceObsSpace
  *${reduce_obs_space} # Either *regionalReduceObsSpace or *globalReduceObsSpace

_round robin dist: &RoundRobinDistribution
  name: RoundRobin

_halo dist: &HaloDistribution
  name: Halo
  halo size: $max_hloc

_obs space: &ObsSpace
  #obs perturbations seed: 1
 #io pool:
 #  write multiple files: true
 #  max pool size: 1024
  distribution: *${obsDistribution} # either *HaloDistribution or *RoundRobinDistribution

_obs error diagonal: &ObsErrorDiagonal
  covariance model: diagonal
  # Note: the same 'obs perturbations seed' must be used for all members for the 'zero-mean perturbations' option to work
  #zero-mean perturbations: true
  #member: 1
  #number of members: 1
_clear crtm: &clearCRTMObsOperator
  name: CRTM
  SurfaceWindGeoVars: uv
  Absorbers: [H2O, O3]
  linear obs operator:
    Absorbers: [H2O]
  obs options: &CRTMObsOptions
    EndianType: little_endian
    CoefficientPath: $CRTM_COEFFS_DIR #/glade/work/guerrett/pandac/fixed_input/crtm_bin/
    IRVISlandCoeff: IGBP #USGS
_cloudy crtm: &cloudyCRTMObsOperator
  name: CRTM
  SurfaceWindGeoVars: uv
  Absorbers: [H2O, O3]
  Clouds: [Water, Ice, Rain, Snow, Graupel]
  Cloud_Seeding: true
  linear obs operator:
    Absorbers: [H2O]
    Clouds: [Water, Ice, Rain, Snow, Graupel]
  obs options:
    <<: *CRTMObsOptions
_get values: &GetValues
  nnearest: 3
_blank: null # not an anchor, so is this needed?
EOF
