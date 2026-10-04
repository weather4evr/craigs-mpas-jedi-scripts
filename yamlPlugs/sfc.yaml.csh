#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
- obs space:
    <<: *ObsSpace
    name: SfcPCorrected
    _obsdatain: &ObsDataIn
      engine:
        type: H5File
        obsfile: $inputDataFile
    _obsdataout: &ObsDataOut
      engine:
        type: H5File
        obsfile: $outputDataFile
    obsdatain: *ObsDataIn
    obsdataout: *ObsDataOut
    simulated variables: &simulatedVars [stationPressure]
  obs error: *ObsErrorDiagonal
  obs operator:
    name: SfcPCorrected
    da_psfc_scheme: UKMO   # or WRFDA
   #observation alias file: obsop_name_map.yaml
  linear obs operator:
    name: Identity
    observation alias file: obsop_name_map.yaml
  get values:
    <<: *GetValues
  obs filters:
  - filter: PreQC
    maxvalue: 3
  - filter: Difference Check
    reference: MetaData/stationElevation
    value: GeoVaLs/surface_altitude
    threshold: 200.0
  - filter: Bounds Check
    filter variables:
    - name: stationPressure
    test variables:
    - name: GeoVaLs/observable_domain_mask
    flag all filter variables if any test variable is out of bounds: true
    minvalue: 0.0
    maxvalue: 0.1
  - filter: Gaussian Thinning
    horizontal_mesh: $horiz_thin
    vertical_mesh: $vert_thin
  - filter: Background Check
    threshold: $bgchk_thresh #5.0
    <<: *multiIterationFilter
 #- *reduceObsSpace
EOF

#if ( $assimOrEval == eval ) then
#  cat >> $output_fname << EOF2
#  - filter: Perform Action
#    filter variables: *simulatedVars # [airTemperature, windEastward, windNorthward, specificHumidity]
#    action:
#      name: passivate
#EOF2
#endif
