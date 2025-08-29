#!/bin/csh

#-----------------------------------------------------------------------
# This script has namelist templates that can be filled-in on the 
# fly by setting environmental variables
# It has two input arguments (see below):
#  $1: the namelist to fill
#  $2: the directory in which to put the namelist
#-----------------------------------------------------------------------

set DATE        = $DATE       # From driver.csh, ccyymmddhhnn
set FCST_RANGE  = $FCST_RANGE # From driver.csh, in minutes

# Need to specify defaults for variables defined in scripts other than driver.csh

#MPAS defaults
if ( ! $?case_number          )  set case_number = -1
if ( ! $?config_stop_time     )  set config_stop_time = `${TOOL_DIR}/da_advance_time.exe ${DATE} 0 -w`
if ( ! $?config_static_interp )  set config_static_interp = .false.
if ( ! $?config_vertical_grid )  set config_vertical_grid = .false.
if ( ! $?config_met_interp    )  set config_met_interp    = .false.
if ( ! $?config_input_sst     )  set config_input_sst     = .false.
if ( ! $?config_frac_seaice   )  set config_frac_seaice   = .false.
if ( ! $?config_input_name    )  set config_input_name    = 'dum'
if ( ! $?config_output_name   )  set config_output_name   = 'dum'
if ( ! $?num_mpas_cells       )  set num_mpas_cells = -1
if ( ! $?num_ungrib_vertical_levels ) set num_ungrib_vertical_levels = 1

if ( ! $?update_sst_interval )    set update_sst_interval = none
if ( ! $?mpas_restart       )     set mpas_restart = .false.
if ( ! $?config_do_DAcycling )    set config_do_DAcycling = .false.
if ( ! $?time_step )              set time_step = 90000000.0
if ( ! $?config_len_disp )        set config_len_disp = 900000000.0
if ( ! $?radiation_frequency )    set radiation_frequency = 15000

#####

# MPAS namelist variables
set START_DATE_MPAS = `${TOOL_DIR}/da_advance_time.exe $DATE 0 -w`
set END_DATE_MPAS   = `${TOOL_DIR}/da_advance_time.exe $DATE ${FCST_RANGE}m -w`

if ( $update_sst_interval == none ) then
   set local_update_sst = .false.
else
   set local_update_sst = .true.
endif

if ( $MPAS_REGIONAL =~ *true* || $MPAS_REGIONAL =~ *TRUE* ) then
   set config_blend_bdy_terrain = .true. # only used for init_atmosphere
   set config_fg_interval = `expr $LBC_FREQ \* 3600` # seconds only used for init_atmosphere
   set config_apply_lbcs = .true. # only used when running MPAS
else
   set config_blend_bdy_terrain = .false.
   set config_fg_interval = 86400 # seconds
   set config_apply_lbcs = .false.
endif

# For SST, config_fg_interval has to match the output_interval of the surface stream
#  which is 24 hours (86400 seconds)
if ( $case_number == 8 ) then
   set config_fg_interval = 86400 # seconds
endif
# If we're creating a static.nc file, we don't want terrain blending. 
# Ideally, init_atmosphere wouldn't even get this far in the code, to attempt to do this,
#  but it does, so config_blend_bdy_terrain must be false to avoid the attempted blending.
if ( $config_static_interp =~ *true* || $config_static_interp =~ *TRUE* ) then
   set config_blend_bdy_terrain = .false.
endif

set z_top_meters = `expr $z_top_km \* 1000` # $z_top_km from driver.csh

#----------------------------------------------------------
# Set PIO stride.  #  This is a moving target that depends
#   on the number of processors used.
# Currently, num_mpas_cells is only set in run_mpas_init.csh and run_mpas.csh
#   and will default to -1 otherwise (see top of this script)
#----------------------------------------------------------
if ( $num_mpas_cells == 6488066 ) then
   if ( $1 == "mpas_init" || $1 == "MPAS_init" ) then
      set config_pio_num_iotasks = 32 #36 # use this for 15-/3-km grid with 516 processors
      set config_pio_stride      = 16
   else
      set config_pio_num_iotasks = 128 #32 #36 
      set config_pio_stride      = 48  #16
   endif
else if ( $num_mpas_cells == 2621442 ) then
   set config_pio_num_iotasks = 36  # global uniform 15-km mesh with 576 processors
   set config_pio_stride      = 16
else if ( $num_mpas_cells == 65536002 ) then
   if ( $1 == "mpas_init" || $1 == "MPAS_init" ) then
      set config_pio_num_iotasks = 128 # use this for 3-km grid global with 2560 processors
      set config_pio_stride      = 20
   else
      set config_pio_num_iotasks = 164 # use this for 3-km global grid with 20992 processors
      set config_pio_stride      = 128 
   endif
else
   set config_pio_num_iotasks = 0
   set config_pio_stride      = 1
endif

#---------------------------------------

# For some reason, when using array syntax, the output files written
# by this script aren't in the correct directory. So pass-in the proper
# directory and cd to it.
set rundir = $2
cd $rundir

echo "Filling Namelist for $1"

if ( $1 == "mpas" || $1 == "MPAS" ) then
   goto MPAS
else if ( $1 == "mpas_init" || $1 == "MPAS_init" ) then
   goto MPAS_init
else
   echo "wrong usage"
   echo "use as $0 (mpas,mpas_init)"
   exit
endif

#--------------------------------------------
# MPAS_initialization namelist.input
#--------------------------------------------

MPAS_init:

rm -f ./namelist.init_atmosphere
cat > ./namelist.init_atmosphere << EOF
&nhyd_model
   config_init_case       = ${case_number} 
   config_start_time      = '${START_DATE_MPAS}'
   config_stop_time       = '${config_stop_time}'
   config_theta_adv_order = 3
   config_coef_3rd_order = 0.25
   config_interface_projection = 'layer_integral'
/

&dimensions
   config_nvertlevels     = $num_mpas_vert_levels
   config_nsoillevels     = $num_mpas_soil_levels
   config_nfglevels       = $num_ungrib_vertical_levels
   config_nfgsoillevels   = $num_ungrib_soil_levels
/

&data_sources
   config_geog_data_path  = '${WPS_GEOG_DIR}/'
   config_met_prefix      = '${ungrib_prefx_model}'
   config_sfc_prefix      = '${ungrib_prefx_sst}'
   config_fg_interval     = ${config_fg_interval},
   config_landuse_data  = 'MODIFIED_IGBP_MODIS_NOAH'
   config_topo_data     = 'GMTED2010'
   config_vegfrac_data = 'MODIS'
   config_albedo_data = 'MODIS'
   config_maxsnowalbedo_data = 'MODIS'
   config_supersample_factor = 3
   config_use_spechumd  = false
/

&vertical_grid
   config_ztop            = ${z_top_meters}.0 
   config_nsmterrain      = 1
   config_smooth_surfaces = .true.
   config_dzmin = 0.3
   config_nsm = 30
   config_tc_vertical_grid = .true.
   config_blend_bdy_terrain = $config_blend_bdy_terrain
   config_specified_zeta_levels = "$vert_levels_file"
/

&interpolation_control
    config_extrap_airtemp = 'linear'
/

&preproc_stages
   config_static_interp   = $config_static_interp 
   config_native_gwd_static = $config_static_interp
   config_vertical_grid   = $config_vertical_grid
   config_met_interp      = $config_met_interp
   config_input_sst       = $config_input_sst
   config_frac_seaice     = $config_frac_seaice
/

&io
   config_pio_num_iotasks    = $config_pio_num_iotasks ! use this for 15-/3-km grid
   config_pio_stride         = $config_pio_stride
/
   config_pio_num_iotasks    = 1 !36
   config_pio_stride         = 1 !16

&decomposition
   config_block_decomp_file_prefix = '${graph_info_prefx}'
/
EOF

exit 0

#--------------------------------------------
# MPAS namelist.input
#--------------------------------------------

MPAS:

rm -f ./namelist.atmosphere
cat > ./namelist.atmosphere << EOF2
&nhyd_model
    config_dt = $time_step
    config_run_duration = '${FCST_RANGE}:00'
    config_start_time   = '${START_DATE_MPAS}'
    config_stop_time    = '${END_DATE_MPAS}'
    config_time_integration_order = 2
    config_split_dynamics_transport = .true.
    config_number_of_sub_steps = 4
    config_dynamics_split_steps = 3
    config_h_mom_eddy_visc2    = 0.0
    config_h_mom_eddy_visc4    = 0.0
    config_v_mom_eddy_visc2    = 0.0
    config_h_theta_eddy_visc2  = 0.0
    config_h_theta_eddy_visc4  = 0.0
    config_v_theta_eddy_visc2  = 0.0
    config_horiz_mixing        = '2d_smagorinsky'
    config_len_disp            = ${config_len_disp}
    config_visc4_2dsmag        = 0.05
    config_w_adv_order         = 3
    config_theta_adv_order     = 3
    config_scalar_adv_order    = 3
    config_u_vadv_order        = 3
    config_w_vadv_order        = 3
    config_theta_vadv_order    = 3
    config_scalar_vadv_order   = 3
    config_scalar_advection    = .true.
    config_positive_definite   = .false.
    config_monotonic           = .true.
    config_coef_3rd_order      = 0.25
    config_epssm               = 0.1
    config_smdiv               = 0.1
/

&damping
    config_zd = 22000.0
    config_xnutr = 0.2
/

&io
    config_pio_num_iotasks    = $config_pio_num_iotasks ! use this for 15-/3-km grid
    config_pio_stride         = $config_pio_stride
/

&decomposition
    config_block_decomp_file_prefix = '${graph_info_prefx}'
/

&restart
    config_do_restart = ${mpas_restart}    ! Shouldn't be true for very first cycle, but true all other times, unless cold start (then false)
    config_do_DAcycling = ${config_do_DAcycling}
/

&printout
    config_print_global_minmax_vel  = true
    config_print_detailed_minmax_vel = true
    config_print_global_minmax_sca  = true
/

&limited_area
    config_apply_lbcs = $config_apply_lbcs
/

&IAU
    config_IAU_option = 'off'
    config_IAU_window_length_s = 21600.
/

&physics
    config_sst_update          = ${local_update_sst}
    config_sstdiurn_update     = .false.
    config_deepsoiltemp_update = .false.
    config_radtlw_interval     = '00:${radiation_frequency}:00'
    config_radtsw_interval     = '00:${radiation_frequency}:00'
    config_o3climatology       = .true.
    config_bucket_update       = 'none' !'1_00:00:00'
    config_microp_re           = .true.
    config_sfc_albedo          = .true.
    config_sfc_snowalbedo      = .true.
    config_frac_seaice         = .true.
    config_physics_suite       = '${physics_suite}'
    config_microp_scheme       = '${config_microp_scheme}'
    config_convection_scheme   = 'cu_ntiedtke'
    config_pbl_scheme          = 'bl_mynn'
    config_gwdo_scheme         = 'bl_ysu_gwdo'
    config_sfclayer_scheme     = 'sf_mynn'
    config_lsm_scheme          = 'sf_noah'
/

&soundings
    config_sounding_interval = 'none'
/

EOF2

exit 0

#######

exit 0
