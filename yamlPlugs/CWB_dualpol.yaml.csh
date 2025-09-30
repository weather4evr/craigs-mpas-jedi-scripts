#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
- obs space:
    <<: *ObsSpace
    name: Refl10cm
    _obsdatain: &ObsDataIn
      engine:
        type: H5File
        obsfile: $inputDataFile
    _obsdataout: &ObsDataOut
      engine:
        type: H5File
        obsfile: $outputDataFile
    obsdatain:
      <<: *ObsDataIn
    obsdataout: *ObsDataOut
    simulated variables: &simulatedVars [equivalentReflectivityFactor]
  obs error: *ObsErrorDiagonal
##<<: *heightAndHorizObsLocCloud
  obs operator:
    name: VertInterp
    observation vertical coordinate: height
    vertical coordinate: geometric_height
    interpolation method: linear
   #name: PPRO
   #microphysics option: NSSL
   #use variational method: false
   #var_rain_mixing_ratio: mixing_ratio_of_rain
   #var_snow_mixing_ratio: mixing_ratio_of_snow
   #var_graupel_mixing_ratio: mixing_ratio_of_graupel
   #var_hail_mixing_ratio: mixing_ratio_of_hail
   #var_rain_number_concentration: rain_number_concentration
   #var_snow_number_concentration: snow_number_concentration
   #var_graupel_number_concentration: graupel_number_concentration
   #var_hail_number_concentration: hail_number_concentration
   #var_graupel_vol_mixing_ratio: volume_mixing_ratio_of_graupel_in_air
   #var_hail_vol_mixing_ratio: volume_mixing_ratio_of_hail_in_air
  get values:
    <<: *GetValues
  obs filters:
  - filter: PreQC
    maxvalue: 3
  - filter: Bounds Check
    filter variables:
    - name: equivalentReflectivityFactor
    test variables:
    - name: GeoVaLs/observable_domain_mask
    flag all filter variables if any test variable is out of bounds: true
    minvalue: 0.0
    maxvalue: 0.1

  - filter: Perform Action
    filter variables:
    - name: equivalentReflectivityFactor
    action:
      name: assign error
      error parameter: 3.0

  - filter: Bounds Check
    filter variables:
    - name: equivalentReflectivityFactor
    maxvalue: 75.0
    minvalue: -15.0

  - filter: Background Check
    threshold: $bgchk_thresh #5.0

    <<: *multiIterationFilter
  - *reduceObsSpace
EOF

if ( $assimOrEval == eval ) then
  cat >> $output_fname << EOF2
  - filter: Perform Action
    filter variables: *simulatedVars # [airTemperature, windEastward, windNorthward, specificHumidity]
    action:
      name: passivate
EOF2

endif

