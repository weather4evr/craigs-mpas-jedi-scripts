#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
- obs space:
    <<: *ObsSpace
    name: ahi_himawari8
    _obsdatain: &ObsDataIn
      engine:
        type: H5File
        obsfile: $inputDataFile #./aircraft_obs_${DATE}.h5
    _obsdataout: &ObsDataOut
      engine:
        type: H5File
        obsfile: $outputDataFile #Data/obsout_omb_aircraft.h5
    obsdatain:
      <<: *ObsDataIn
    obsdataout: *ObsDataOut
    simulated variables: [brightnessTemperature]
    channels: &ahi_himawari8_channels $channels # 8-10
  obs error: *ObsErrorDiagonal
  obs operator:
    <<: *cloudyCRTMObsOperator
    obs options:
      <<: *CRTMObsOptions
      Sensor_ID: ahi_himawari8
  get values:
    <<: *GetValues
  obs filters:
  - filter: PreQC
    maxvalue: 0
# - filter: Bounds Check
#   filter variables:
#   - name: brightnessTemperature
#   test variables:
#   - name: GeoVaLs/observable_domain_mask
#   flag all filter variables if any test variable is out of bounds: true
#   minvalue: 0.0
#   maxvalue: 0.1
  - filter: Gaussian Thinning
    horizontal_mesh: $horiz_thin
  - filter: Background Check
    threshold: $bgchk_thresh #3.0
    <<: *multiIterationFilter
  - *reduceObsSpace
  - filter: Domain Check
    where:
    - variable:
        name: MetaData/sensorZenithAngle
      maxvalue: 60.0
  - filter: GOMsaver
    filename: ${jedi_output_dir}/geovals_ahi_himawari8.nc4
  - filter: YDIAGsaver
    filename: ${jedi_output_dir}/ydiag_ahi_himawari8.nc4
    filter variables:
    - name: brightness_temperature_assuming_clear_sky
      channels: *ahi_himawari8_channels
    - name: weightingfunction_of_atmosphere_layer
      channels: *ahi_himawari8_channels
    - name: pressure_level_at_peak_of_weightingfunction
      channels: *ahi_himawari8_channels
    - name: brightness_temperature_jacobian_air_temperature
      channels: *ahi_himawari8_channels
    - name: brightness_temperature_jacobian_humidity_mixing_ratio
      channels: *ahi_himawari8_channels
    - name: brightness_temperature_jacobian_surface_emissivity
      channels: *ahi_himawari8_channels
    - name: brightness_temperature_jacobian_surface_temperature
      channels: *ahi_himawari8_channels
  # Assign obsError.
  - filter: Perform Action
    <<: *multiIterationFilter
    filter variables:
    - name: brightnessTemperature
      channels: *ahi_himawari8_channels
    action:
      name: assign error
      _symmetric cld: &ahi_g16_SymmCld
        x0: [0.5, 0.5, 0.5]
        x1: [17.0, 20.5, 24.5]
        err0: [3.21, 3.11, 2.47]
        err1: [12.57, 14.57, 17.09]
      error function:
        name: ObsFunction/ObsErrorModelRamp
        channels: *ahi_himawari8_channels
        options:
          <<: *ahi_g16_SymmCld
          channels: *ahi_himawari8_channels
          xvar:
  #         name: ObsFunction/SymmCldImpactIR  # Okamoto (2014) error model
            name: ObsFunction/SymmCldImpactBTlim # Harnisch et al. (2016) error model
            channels: *ahi_himawari8_channels
            options:
              channels: *ahi_himawari8_channels
              btlim: [235.2, 245.7, 258.3] # comment out if using Okamoto (2014) error model
EOF
