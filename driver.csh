#!/bin/csh
#PBS -S /bin/csh
#PBS -N driver
#PBS -A NMMM0015
#PBS -l walltime=2:00
#PBS -q main
#PBS -l job_priority="regular"
#PBS -o ./output_file
#PBS -j oe 
#PBS -k eod 
#PBS -l select=1:ncpus=1:mpiprocs=1
#PBS -m n    
#PBS -M schwartz@ucar.edu
#PBS -V 
#

# Set some basic info about the machine
setenv run_cmd              "mpiexec" #"mpirun.lsf" # General job submission command for the machine
setenv num_procs_per_node   128 # Number of processors in each node (system-dependent)

# Total number of processors, processors per node, and wallclock (minutes) for various programs
setenv mpas_init_num_procs  128 # init_atmosphere
setenv mpas_init_num_procs_per_node  $num_procs_per_node # Number of processors per node you want to use for init_atmosphere (MPAS init)
setenv mpas_init_walltime  10

setenv mpas_num_procs    256 # atmosphere_model
setenv mpas_num_procs_per_node  $num_procs_per_node # Number of processors per node you want to use for MPAS Model forecasts
setenv mpas_walltime       6 
setenv mpas_num_procs_free_fcst $mpas_num_procs # for free forecast on the potentially higher-resolution mesh

setenv jedi_variational_num_procs   512 # JEDI variational (EnVar/hybrid/3DVar)
setenv jedi_variational_num_procs_per_node  64
setenv jedi_walltime_variational            10

   # LETKF in "observer" mode. Need to use the same number of processors for the mean and members
   # But, number of processors per node can differ for mean and the members
setenv jedi_enkf_num_procs_observer      1024  # JEDI EnKF (LETKF/GETKF)
setenv jedi_enkf_num_procs_per_node_observer_mean 64
setenv jedi_enkf_num_procs_per_node_observer_members $num_procs_per_node
setenv jedi_walltime_enkf_observer       10

   # LETKF "solver" ; these are used for just solver and for everything if all_at_once == true
setenv jedi_enkf_num_procs_solver        1024  # JEDI EnKF (LETKF/GETKF)
setenv jedi_enkf_num_procs_per_node_solver 64 #$num_procs_per_node
setenv jedi_walltime_enkf_solver         20

# Account numbers
setenv mpas_account  "NMMM0073" 
setenv jedi_account  $mpas_account

set jedi_queue = "main"  #full name: main@chadmin1.ib0.cheyenne.ucar.edu" 
set jedi_priority = "regular"
set mpas_queue = "main"
set mpas_priority = "economy"

# Decide what to run (run if true):
setenv RUN_UNGRIB              false
   set stages_ungrib = ( deterministic ensemble ) #( deterministic ensemble )

setenv RUN_MPAS_INITIALIZE     false
   set stages_mpas_init = ( deterministic ensemble ) #( deterministic ensemble )

setenv RUN_JEDI_ENKF   true
   setenv all_at_once  false # if true, run the EnKF "all at once", with just one execution of run_jedi.csh
   setenv do_oma       false #  currently working; keep false

setenv RUN_JEDI_EnVar  false

setenv RUN_MPAS_ENS  true  # Runs all ensemble members forward in time
   set run_ens_for = next_cycle  # (next_cycle,forecast); next_cycle uses $FCST_RANGE_DA and $ENS_SIZE below; forecast uses $FCST_RANGE
   # next two options only used if $run_ens_for = forecast
   set num_members_to_run = 30 # 1 # Can be < $ENS_SIZE if $run_ens_for = forecast (see below) if you only want fcsts for selected members
   set rand_num_script = ~schwartz/NCL/rand_num.ncl  # Script to generate random numbers to run MPAS for randomly-selected members

setenv RUN_MPAS_DETERMINISTIC false # Runs a deterministic forecast forward in time
   set run_det_for = next_cycle  # (next_cycle,forecast); next_cycle uses $FCST_RANGE_DA; forecast uses $FCST_RANGE

setenv RUN_BUMP         false # Run JEDI's BUMP for localization files. Just need to read an init.nc file valid at any date

######################################
#Directories pointing to source code #
######################################

setenv   SCRIPT_DIR  /glade/u/home/schwartz/MPAS_JEDI/scripts  # Location of all these .csh scripts
setenv   myname      ${SCRIPT_DIR}/driver.csh # Full pathname of this script; needed in case we resubmit this script during cycling

set REL_DIR = /glade/work/schwartz # useful variable for specifying paths; otherwise not used

#setenv   MPAS_JEDI_BUNDLE_DIR  /glade/campaign/mmm/parc/jban/CWA/2025/bundle/basedon_v302 #${REL_DIR}/JEDI/derecho/2025may14_mpas_bundle_rkong
setenv   MPAS_JEDI_BUNDLE_DIR  /glade/work/schwartz/JEDI/derecho/mpas_bundle_SP_jban_4july2025
#setenv   MPAS_JEDI_BUNDLE_DIR  /glade/campaign/mmm/parc/ivette/pandac/codeBuild/mpasBundle_13May2025_IRvarbc_obsErrors_btlim
setenv   MPAS_CODE_DIR         $MPAS_JEDI_BUNDLE_DIR #${REL_DIR}/MPAS/derecho/MPASv7.0_20210111_mpas_bundle_scaleAwareNewTiedtke_withUpdatedForcing
# Specify location of the .TBL, .DBL, and 'DATA' files needed by MPAS. They should be consistent with the MPAS build.
# If using MPAS built outside of MPAS-JEDI, probably in $MPAS_CODE_DIR, but if using MPAS built within MPAS-JEDI, they could be in a few places
setenv   MPAS_TABLE_DIR        ${MPAS_CODE_DIR}/build/MPAS/core_atmosphere
setenv   WPS_DIR               ${REL_DIR}/WRF/derecho/WPS4.1_parallel   # Need ungrib.exe for MPAS initialization
setenv   TOOL_DIR              /glade/u/home/schwartz/utils/derecho  # Location of ./da_advance_time.exe, built from WRFDA

setenv ENS_AVERAGE_EXEC        /glade/u/home/schwartz/average_netcdf_files_parallel_mpas_efficient.x # MPI executable to take an average of MPAS NETCDF files
setenv NETCDF_CONCATENATE_EXEC /glade/u/home/schwartz/concatenate_netcdf/concatenate_netcdf_files.x # MPI executable to concatenate UFO files from all processors into one file
setenv THINNING_HofX_EXEC      /glade/u/home/schwartz/MPAS_JEDI/scripts/thinning_hofx.py

# Environments--assumes you have a "default" environment that can be "restore"d ('module restore default'). This is just the general environment you use; make one if you don't have one.
setenv default_environment_file   ${SCRIPT_DIR}/default_environment.txt # Default login environment; will be created then sourced.
setenv jedi_environment_file  ${MPAS_JEDI_BUNDLE_DIR}/code/mpas-bundle/env-setup/gnu-derecho.csh     # File with the JEDI environment. Must already be there.
setenv mpasjedi_library_path  ${MPAS_JEDI_BUNDLE_DIR}/build/lib  # Full path location to libmpasjedi.so that is built when compiling JEDI; needed on Derecho
setenv run_cmd_jedi           mpiexec # MPI command to run jedi, could differ from $run_cmd (above) that is based on the machine
setenv mpas_compiled_within_jedi    true  # (true, false) If true, use the MPAS model/init executables compiled within mpas-bundle using JEDI environment. If false use jedi_environment_file for mpas environment
   # next two options only used if $mpas_compiled_within_jedi = Falsle
   setenv mpas_environment_file      ${SCRIPT_DIR}/mpas_environment.txt # Environment used to compile MPAS (outside JEDI context); file will be created below
   set mpas_modules = ( ncarenv/23.09   craype/2.7.23 intel-oneapi/2023.2.1 ncarcompilers/1.0.0 cray-mpich/8.1.27 hdf5-mpi/1.12.2 netcdf-mpi/4.9.2 parallelio/2.6.2 parallel-netcdf/1.12.3 ) # if mpas_modules = ( "default" ), use the default environment. Otherwise, set to the list of modules used to compile MPAS (outside JEDI context)

############################################################
# This controls the top-level directory of the experiment  #
############################################################

setenv DETERMINISTIC_MESH   20_2km_small   # EnVar mesh, typically something like 15km_mesh 
setenv ENSEMBLE_MESH   $DETERMINISTIC_MESH # 15km_mesh   # EnKF/ensemble mesh; could be same as $DETERMINISTIC_MESH

setenv EXPT           expt_tcwa2_ahi+RAD # name of the experiment
setenv EXP_DIR_TOP   /glade/derecho/scratch/schwartz/CWA/2025/${DETERMINISTIC_MESH}/${EXPT}  #Directory where most things run

################################################################################
# Time/Experiment/Cycling control 
# Dates are ccyymmddhhnn (e.g., 201904251200) to allow for sub-hourly cycling.
# All times/intervals are in minutes.
# If you do 'setenv start_init $start_init' and 
#  'setenv end_init $start_init', that is one way to cycle. Then in the shell,
#  do 'setenv start_init ccyymmddhh' followed by './driver.csh'. Then ./driver.csh
#  will resubmit itself to do the next cycle, incrementing start_init according to $CYCLE_PERIOD.
#  This is the approach I typically use.  See the very end of this script.
# Alternatively, you could set start_init and end_init to be different, in which
#  case the below loop will cycle over all these dates, incrementing according to
#  $CYCLE_PERIOD.  Some slight modifications to dependency conditions would need
#  to be made in this case, and you will submit lots of jobs to the system.
################################################################################

setenv FIRST_DATE    202206221800 # Fixed for a set of experiments. First date of an MPAS forecast (cold-start forecast initialized at this time to start things off).
setenv LAST_DATE     202206291100 # Fixed for a set of experiments. The last date for an analysis or forecast.

setenv start_init    $start_init # controls the cycling in below loop. should be >= $FIRST_DATE
setenv end_init      $start_init

setenv CYCLE_PERIOD   60  #Time between analyses in minutes
setenv FCST_RANGE_DA  $CYCLE_PERIOD   #Length of MPAS forecasts during cycling (minutes), should be >= $CYCLE_PERIOD
setenv FCST_RANGE     360   #Length of MPAS FREE FORECASTS in minutes; also used for LBC length if regional mesh
setenv diag_output_interval    $CYCLE_PERIOD # Frequency to output diag.nc files (minutes)
setenv restart_output_interval $CYCLE_PERIOD # Frequency to output restart.nc or mpasout.nc files (minutes)
setenv use_2stream_IO   true # If true, use 2-stream MPAS/IO, and produce mpasout* files, using output stream "da_state" and "invariant" files

setenv update_sst  true    # Periodically update SST from external data, like NCEP? (true or false)
   setenv update_sst_hours  "00 06 12 18" # hours of the day (UTC; 2 digits) when you want to update SST from external file

setenv MPAS_INPUT_SOURCE_ENS  enkf  # Initial condition source for ensemble MPAS (enkf, external)
setenv MPAS_INPUT_SOURCE_DET  envar # Initial condition source for determinisic MPAS run (enkf, envar, external)

# Ensemble size
set ie =  1  # What ensemble member to start with?  Usually set to 1 with little need to change.
setenv ENS_SIZE     30 # Ensemble size in EnKF/EDA/free forecasts, etc.

####################################################
# Namliest/streams/yaml templates
#  You probably need to edit these files for your 
#  runs, but once they're set, little need to change
####################################################
setenv  NAMELIST_TEMPLATE    ${SCRIPT_DIR}/namelist_template.csh  #Most namelist variables hard-wired here, some filled on-the-fly.
setenv  STREAMS_TEMPLATE     ${SCRIPT_DIR}/streams_template.csh   #Most streams variables hard-wired here, some filled on-the-fly.
setenv  JEDI_YAML_PLUGS      ${SCRIPT_DIR}/yamlPlugs              #Directory with lots of .yaml.csh files. Have a look; they control the JEDI configurations.

    # These probably don't need changing very often
setenv  JEDI_GEOVARS_YAML    ${MPAS_JEDI_BUNDLE_DIR}/code/mpas-bundle/mpas-jedi/test/testinput/namelists/geovars.yaml
setenv  JEDI_KEPTVARS_YAML   ${MPAS_JEDI_BUNDLE_DIR}/code/mpas-bundle/mpas-jedi/test/testinput/namelists/keptvars.yaml
setenv  OBSOP_NAME_MAP_YAML  ${MPAS_JEDI_BUNDLE_DIR}/code/mpas-bundle/mpas-jedi/test/testinput/obsop_name_map.yaml
setenv  RADAR_DA_COEFFS       /glade/derecho/scratch/jban/regional_mpasjedi/jban_letkf_3kmTW_PPRO_nssl_20220624/MPAS-Workflow/config/mpas

#####################################################################################################
# These control input into the sequence of scripts. Specifically, specify external models to provide
# ICs at start of cycling, as well as SST updates and, if regional, LBCs. 
# Also specify locations of observation files.
#####################################################################################################

# Specify the external model providing ICs for deterministic and ensemble (e.g., GFS, GEFS, etc.)
# This is the model providing initial conditions for MPAS for a cold-start (no DA), $FIRST_DATE, 
#  and for LBCs if a regional simulation. These names should be used in the corresponding VTable files 
#  in VTABLE_DIR (e.g., Vtable.GFS, Vtable.GEFS), or, more specifically
#  Vtable.${EXTERNAL_ICS_DETERMINISTIC}, Vtable.${EXTERNAL_ICS_ENS}
setenv  VTABLE_DIR                  ${SCRIPT_DIR}/VTables
setenv  EXTERNAL_ICS_DETERMINISTIC  GFS_FV3_withSpechum #GFS_FV3
setenv  EXTERNAL_ICS_ENS            GEFS_withSpechum #GEFS
setenv  num_ungrib_soil_levels  4  # number of soil levels in cold start files (almost always 4)

# Location of input GRIB data--your responsibility to get the files there. Names of the files don't matter much.
# For deterministic: directories "by initialization time": e.g., /glade/derecho/scratch/schwartz/MPAS/GFS_grib_0.25deg/2023052300
# For ensemble: directories "by initialization time and ensemble member": e.g., /glade/derecho/scratch/schwartz/MPAS/GEFS_0p5_degree_grib_files/2023052300/ens_3
# These directories need to be there, with the data. For ensemble, the member needs to go last (after the date) and is not a specified number of digits (e.g. ens_1 rather than ens_01, ens_11 rather than ens_011, ens_123 rather than ens_0123)
setenv  GRIB_INPUT_DIR_DETERMINISTIC      /glade/derecho/scratch/schwartz/GFS_grib_0.25deg
setenv  GRIB_INPUT_DIR_ENS                /glade/derecho/scratch/schwartz/GEFS_0p5_degree_grib_files
setenv  GRIB_INPUT_DIR_DETERMINISTIC_SST  $GRIB_INPUT_DIR_DETERMINISTIC
setenv  GRIB_INPUT_DIR_ENS_SST            $GRIB_INPUT_DIR_ENS
setenv  WPS_GEOG_DIR    /glade/campaign/mmm/wmr/mpas_static # Path to static datasets for MPAS initialization

setenv  ungrib_prefx_model "FILE"  # File prefix for output name of ungrib.exe (probably don't need to change)
setenv  ungrib_prefx_sst   "SST"   

setenv  OB_DIR  /glade/campaign/mmm/parc/schwartz/CWA/2025/ob  #Top-level directory containing obs (sub-dirs by date in ccyymmddhhnn)

####################################################
# Where output of ungrib/init_atmosphere is stored
####################################################
# These directories will be created using the following convention:
# For deterministic: directories "by date": e.g., /glade/derecho/scratch/schwartz/MPAS/ungrib_deterministic/2023052300
# For ensemble: directories "by date and ensemble member": e.g., /glade/derecho/scratch/schwartz/MPAS/ungrib_ens/2023052300/ens_3
setenv UNGRIB_OUTPUT_DIR_DETERMINISTIC  /glade/derecho/scratch/schwartz/CWA/2025/ungrib_deterministic 
setenv UNGRIB_OUTPUT_DIR_ENS            /glade/derecho/scratch/schwartz/CWA/2025/ungrib_ens 
setenv MPAS_INIT_DETERMINISTIC_OUTPUT_DIR_TOP  /glade/derecho/scratch/schwartz/CWA/2025/${DETERMINISTIC_MESH}/mpas_init #Top-level directory holding MPAS initialization files (sub-dirs by date)
setenv MPAS_INIT_ENS_OUTPUT_DIR_TOP            /glade/derecho/scratch/schwartz/CWA/2025/${ENSEMBLE_MESH}/mpas_init #Top-level directory containing ensemble ICs (sub-dirs by date and member)
setenv MPAS_INIT_FREE_FCST_OUTPUT_DIR_TOP  $MPAS_INIT_DETERMINISTIC_OUTPUT_DIR_TOP #Top-level directory containing MPAS init files on grid needed for free forecast (sub-dirs by date)

########################
# MPAS mesh settings
########################

# ----------------------------------------------------------------------------------
# Vertical grid dimensions, same for both the ensemble and determinsitic forecasts
# (putting these variables up here so $num_mpas_vert_levels can be used to define
# the "invariant" files)
# ----------------------------------------------------------------------------------
setenv num_mpas_vert_levels   56   # Number of vertical levels (mass levels; not edges)
setenv num_mpas_soil_levels   4    # Number of soil levels
setenv z_top_km               30   # MPAS model top (km)
setenv vert_levels_file       ${SCRIPT_DIR}/zeta_CWA_2025.txt # File with specified vertical levels; set to "" or remove from config_specified_zeta_levels in namelist if you don't want

# -------------------------------------------------------
# MPAS mesh for deterministic forecasts/DA
# -------------------------------------------------------
setenv num_mpas_cells_deterministic    97301 #163842 #6488066 #40962 #655362
setenv grid_info_dir_deterministic      /glade/campaign/mmm/parc/schwartz/CWA/2025/${DETERMINISTIC_MESH}/grid_mesh  # Directory with graph.info files
setenv graph_info_prefx_deterministic   20_2km_small.graph.info.part. # Files should be in $grid_info_dir_deterministic; must be there
setenv grid_file_netcdf_deterministic   ${grid_info_dir_deterministic}/20_2km_small.grid.nc  # Must be there if static.nc needs to be created
setenv mpas_static_data_file_deterministic  /glade/campaign/mmm/parc/schwartz/CWA/2025/${DETERMINISTIC_MESH}/mpas_init/static.nc  # Can be there or will be created, just needs to be created once.
setenv mpas_invariant_file_deterministic    /glade/campaign/mmm/parc/schwartz/CWA/2025/${DETERMINISTIC_MESH}/mpas_init/invariant_${num_mpas_vert_levels}vertLevels.nc  # You can put it there, or it will be created during initialization, just needs to be created once.

# ------------------------------------------------------------------------------------------------
# MPAS mesh for ensemble forecasts/DA (typically lower or same resolution as deterministic mesh)
# ------------------------------------------------------------------------------------------------
setenv num_mpas_cells_ens          $num_mpas_cells_deterministic #2621442
setenv grid_info_dir_ens           $grid_info_dir_deterministic #/glade/campaign/mmm/parc/schwartz/MPAS/${ENSEMBLE_MESH}/grid_mesh # Directory with graph.info files
setenv graph_info_prefx_ens        $graph_info_prefx_deterministic #x1.${num_mpas_cells_ens}.graph.info.part. # Files should be in $grid_info_dir_ens; must be there
setenv grid_file_netcdf_ens        $grid_file_netcdf_deterministic #${grid_info_dir_ens}/x1.${num_mpas_cells_ens}.grid.nc  # Must be there if static.nc needs to be created
setenv mpas_static_data_file_ens   $mpas_static_data_file_deterministic #/glade/campaign/mmm/parc/schwartz/MPAS/${ENSEMBLE_MESH}/mpas_init/static.nc # # Can be there or will be created
setenv mpas_invariant_file_ens     $mpas_invariant_file_deterministic #$/glade/campaign/mmm/parc/schwartz/MPAS/${ENSEMBLE_MESH}/mpas_init/invariant_${num_mpas_vert_levels}vertLevels.nc  # You can put it there, or it will be created during initialization, just needs to be created once.

# ----------------------------------------------------------------------------
# MPAS mesh for free forecasts; can be higher resolution than analysis grid 
#   i.e., you can do 30-km DA but initialize 15-km forecasts
# ----------------------------------------------------------------------------
setenv   num_mpas_cells_free_fcst       $num_mpas_cells_deterministic
setenv   grid_info_dir_free_fcst        $grid_info_dir_deterministic 
setenv   graph_info_prefx_free_fcst     $graph_info_prefx_deterministic #x1.${num_mpas_cells_free_fcst}.graph.info.part. # Files should be in $grid_info_dir_free_fcst; must be there
setenv   grid_file_netcdf_free_fcst     $grid_file_netcdf_deterministic
setenv   mpas_invariant_file_free_fcst  $mpas_invariant_file_deterministic
setenv   interpolation_weight_file      dummy #weights_30km_mesh_to_15km_mesh.dat  # Weights file for interpolation from one MPAS mesh to another.  Will either be created or used.

#######################################################
# MPAS model namelist settings that are not hard-coded
#######################################################
setenv time_step_deterministic 12.0 # Seconds.  Typically should be 4-6*dx; use closer to 4 for cycling DA
setenv time_step_ens         $time_step_deterministic
setenv time_step_free_fcst   $time_step_deterministic
setenv radiation_frequency_deterministic  15 # Minutes.  Typically the same as dx (for dx = 15 km, 15 minutes)
setenv radiation_frequency_ens $radiation_frequency_deterministic
setenv radiation_frequency_free_fcst $radiation_frequency_deterministic #15
setenv config_len_disp_deterministic  2000. # meters, diffusion length scale, which should reflect finest resolution in mesh
setenv config_len_disp_ens       $config_len_disp_deterministic
setenv config_len_disp_free_fcst $config_len_disp_deterministic
setenv soundings_file       dum #${SCRIPT_DIR}/sounding_locations.txt   # set to a dummy to disable soundings
setenv physics_suite        "convection_permitting" #"mesoscale_reference" #"convection_permitting_wrf390" 
setenv config_microp_scheme   mp_tcwa2 # can put in namelist, or not. if mp_thompson, we need to link more files

setenv MPAS_REGIONAL true  # If true, this is a regional mesh and we need LBCs
setenv LBC_FREQ      3     # hours: LBC frequency

######################
# Parameters for DA
######################

# $OBS_INFO_FILE has a list of observations you want to assimilate. 
# It controls many things.  Have a look--it's easy to understand.
# run_jedi.csh parses the file
setenv OBS_INFO_FILE ${SCRIPT_DIR}/obs_table.txt
setenv ob_time_window   30  # Minutes...the number of minutes on either side of the analysis date to assimilate obs; usually 0.5 * $CYCLE_PERIOD

# ----------------------
# JEDI EnKF/Envar settings
# ----------------------
setenv enkf_type   GETKF      # Either LETKF or GETKF, in capital letters. If GETKF, vertical localization is in model space. Horizontal localization in obs-space for both LETKF and GETKF (in model space for EnVar).
setenv corrlength_model_space 160 # Horizontal Gaspari-Cohn distance at which increment forced to zero (km) for model-space localization in EnVar; obs-space localizations (for all EnKFs) defined in $OBS_INFO_FILE
setenv vertloc_length_model_space  4000.0  # Vertical Gaspari-Cohn distance at which increment forced to zero for model-space localization. Can be scale-height or meters. For EnVar and GETKF.
setenv vertloc_coord_model_space       "height"  # ("height", "pressure" ); pressure really means scale-height; used in GETKF YAML
setenv vertloc_coord_model_space_bump  "height"  # ("height", "scaleheight" ); for BUMP YAML
setenv rtps_inflation_factor    0.9
setenv rtpp_inflation_factor    0.0

# Where does EnVar get its background from?  Options: prior_ens_mean,cycle,cold_start
# Usually set to cycle, which means cycling deterministic EnVar circuit.
# Could also use prior_ens_mean (take mean of the prior ensemble) or cold_start (probably only use for testing)
setenv envar_det_fg_source  cycle # (cycle,prior_ens_mean,cold_start)
setenv num_outer_loops  1    # Number of outer loops for variational minimization  
setenv num_inner_loops  60   # Maximum number of iterations in each outer loop
setenv FOUR_D_ENVAR   false  # (true,false) ... whether to use 4DEnVar
   setenv    ens_fcst_mins    "-180 -120 -60 0 60 120 180"  # Forecast minutes relative to analysis time for FGAT/4DEnVar

# background error covariance for EnVar via BUMP, which uses $corrlength_model_space, $vertloc_length_model_space, and $vertloc_coord_model_space_bump
setenv BE_DIR         /glade/derecho/scratch/schwartz/CWA/2025/${ENSEMBLE_MESH}/bump_files # location of BUMP files
setenv BE_PREFIX      bumploc_${corrlength_model_space}km_${vertloc_length_model_space}${vertloc_coord_model_space_bump} # prefix of BUMP files

# ----------------------
# Stuff for radiance DA
# ----------------------
#setenv CRTM_COEFFS_DIR      /glade/campaign/mmm/parc/liuz/pandac_common/crtm_coeffs/ # need slash at end; JEDI CRTM cofficients
setenv CRTM_COEFFS_DIR      /glade/work/nystrom/Code/JEDI/jcsda_internal/CRTM_V3_coeffs/ # need slash at end; JEDI CRTM cofficients
setenv TLAP_DIR             ${SCRIPT_DIR}/tlap_files  # Directory with text files containing lapse rate information for bias correction needed for MPAS-JEDI
setenv VARBC_CYCLE_PERIOD   $CYCLE_PERIOD # Cycle length for VarBC (minutes). Usually, $CYCLE_PERIOD, but could be longer (like 24 h if doing regional DA).
setenv MAX_VARBC_CYCLE      1440 # Farthest we can go back in time to find VarBC coefficients for a given cycle (minutes)

#If true, always use the bias correction covariances (B_beta) from the first cycle.
# In other words, don't cycle the bias correction covariances. Just use what GSI
# provides at the very start of the cycling period.
setenv use_static_bias_correction_covariance true # (true , false)
   setenv STATIC_BC_DIR   ${EXP_DIR_TOP}/${FIRST_DATE}/envar

#########################################################
# NOTHING BELOW HERE SHOULD NEED CHANGING VERY OFTEN
# (other than setting dependency conditions)
#########################################################

set ff = ( $NAMELIST_TEMPLATE $STREAMS_TEMPLATE $JEDI_GEOVARS_YAML $JEDI_KEPTVARS_YAML $OBSOP_NAME_MAP_YAML $jedi_environment_file )
foreach f ( $ff )
   if ( ! -e $f ) then
     echo "$f doesn't exist. Abort!"
     exit
   endif
end

# Make file with main models and then load them
echo "module --force purge ; module restore default" > $default_environment_file
source $default_environment_file

if ( $mpas_compiled_within_jedi =~ *true* || $mpas_compiled_within_jedi =~ *TRUE* ) then
   cp $jedi_environment_file $mpas_environment_file
else
   if ( $mpas_modules[1] == default ) then
      cp $default_environment_file $mpas_environment_file
   else
      echo "module --force purge ; module load ${mpas_modules} " > $mpas_environment_file
   endif
endif

# Define MPAS file type to cycle
if ( $use_2stream_IO =~ *true* || $use_2stream_IO =~ *TRUE* ) then
   setenv file_type   "mpasout"
else
   setenv file_type   "restart"
endif

#-------------------------

setenv DATE $start_init
while ( $DATE <= $end_init )

   echo "Processing $DATE"

   if ( $RUN_UNGRIB == true ) then
      foreach stage ( $stages_ungrib ) 
         setenv RUN_STAGE   $stage
         if ( $stage == deterministic ) then
	    ${SCRIPT_DIR}/run_ungrib.csh
         endif
         if ( $stage == ensemble ) then
	    foreach mem ( `seq $ie 1 $ENS_SIZE` )
	       ${SCRIPT_DIR}/run_ungrib.csh $mem # send the ensemble member into run_ungrib.csh
	    end
         endif
      end
   endif

   if ( $RUN_MPAS_INITIALIZE == true ) then
      set this_num_needed_nodes = `echo "$mpas_init_num_procs / $mpas_init_num_procs_per_node" | bc`
      foreach stage ( $stages_mpas_init ) 
         if ( $stage == ensemble ) then
            set job_array_str = "-J ${ie}-${ENS_SIZE}" # submit job array for ensemble
         else
	    set job_array_str = ""
         endif
	 setenv RUN_STAGE   $stage
	 set id_init = `qsub -N "init_${stage}_${DATE}" -A "$mpas_account" -q "$mpas_queue" -l job_priority="economy" \
	 	  -l walltime=${mpas_init_walltime}:00 $job_array_str \
	 	  -l "select=${this_num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${mpas_init_num_procs_per_node}" \
	 	   ${SCRIPT_DIR}/run_mpas_init.csh`
        #${SCRIPT_DIR}/run_mpas_init.csh 1
      end
   endif

   if ( $RUN_JEDI_ENKF == true ) then
      set dependency_condition = ""
      if ( $RUN_MPAS_INITIALIZE == true ) then
	 set dependency_condition = "-W depend=afterok:${id_init}"
      endif

      if ( $all_at_once == true ) then
	 setenv JEDI_ANALYSIS_TYPE   enkf_all_at_once
	 set num_needed_nodes = `echo "$jedi_enkf_num_procs_solver / $jedi_enkf_num_procs_per_node_solver" | bc`
	 set id_enkf = `qsub -N "enkf_${DATE}" $dependency_condition -A "$jedi_account"  -q $jedi_queue -l job_priority=${jedi_priority} \
	     -l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${jedi_enkf_num_procs_per_node_solver}" \
	     -l walltime=${jedi_walltime_enkf_solver}:00 ${SCRIPT_DIR}/run_jedi.csh`

      else # call run_jedi.csh 3 times; first for HofX applied to ensemble mean prior, then for HofX applied to members, then EnKF solver

setenv jedi_enkf_num_procs_observer      1024  # JEDI EnKF (LETKF/GETKF)
	 setenv JEDI_ANALYSIS_TYPE   enkf_prior_mean
	 set num_needed_nodes = `echo "$jedi_enkf_num_procs_observer / $jedi_enkf_num_procs_per_node_observer_mean" | bc`
	 set id_enkf = `qsub -N "enkf_${DATE}" $dependency_condition -A "$jedi_account"  -q $jedi_queue -l job_priority=${jedi_priority} \
	     -l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${jedi_enkf_num_procs_per_node_observer_mean}" \
	     -l walltime=${jedi_walltime_enkf_observer}:00 ${SCRIPT_DIR}/run_jedi.csh`

setenv jedi_enkf_num_procs_observer      256  # JEDI EnKF (LETKF/GETKF)
	 setenv JEDI_ANALYSIS_TYPE   enkf_prior_members
	 set dependency_condition = "-W depend=afterok:${id_enkf}"
	#set dependency_condition = ""
	 set num_needed_nodes = `echo "$jedi_enkf_num_procs_observer / $jedi_enkf_num_procs_per_node_observer_members" | bc`
	 set id_enkf = `qsub -N "enkf_${DATE}" $dependency_condition -A "$jedi_account"  -q $jedi_queue -l job_priority=${jedi_priority} \
	     -J ${ie}-${ENS_SIZE} \
	     -l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${jedi_enkf_num_procs_per_node_observer_members}" \
	     -l walltime=${jedi_walltime_enkf_observer}:00 ${SCRIPT_DIR}/run_jedi.csh`

	 setenv JEDI_ANALYSIS_TYPE   enkf
	 set dependency_condition = "-W depend=afterok:${id_enkf}"
	#set dependency_condition = ""
	 set num_needed_nodes = `echo "$jedi_enkf_num_procs_solver / $jedi_enkf_num_procs_per_node_solver" | bc`
	 set id_enkf = `qsub -N "enkf_${DATE}" $dependency_condition -A "$jedi_account"  -q $jedi_queue -l job_priority=${jedi_priority} \
	     -l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${jedi_enkf_num_procs_per_node_solver}" \
	     -l walltime=${jedi_walltime_enkf_solver}:00 ${SCRIPT_DIR}/run_jedi.csh`
      endif

     #${SCRIPT_DIR}/run_jedi.csh
   endif

   if ( $RUN_BUMP == true ) then
      setenv JEDI_ANALYSIS_TYPE   bump
      set num_needed_nodes = `echo "$jedi_variational_num_procs / $jedi_variational_num_procs_per_node" | bc`
      set id = `qsub -A "$jedi_account" -N "run_bump" -l walltime=15:00 -q $jedi_queue \
       -l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${jedi_variational_num_procs_per_node}" ${SCRIPT_DIR}/run_jedi.csh`
     #${SCRIPT_DIR}/run_jedi.csh
   endif

   if ( $RUN_JEDI_EnVar == true ) then
      setenv JEDI_ANALYSIS_TYPE    envar
      set dependency_condition = ""
      #set dependency_condition = "-W depend=afterok:${id}"

      # Now run EnVar.  If prior ensemble still not there, it will fail.
      set num_needed_nodes = `echo "$jedi_variational_num_procs / $jedi_variational_num_procs_per_node" | bc`
      set id_envar = `qsub -A "$jedi_account" -N "envar_${DATE}" -q "$jedi_queue" $dependency_condition \
          -l walltime=${jedi_walltime_variational}:00 -l job_priority=${jedi_priority} \
          -l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${jedi_variational_num_procs_per_node}" ${SCRIPT_DIR}/run_jedi.csh`
	  #-l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${jedi_variational_num_procs_per_node}:mem=109gb" ${SCRIPT_DIR}/run_jedi.csh`
		# -l "select=128:ncpus=4:mpiprocs=4" ${SCRIPT_DIR}/run_jedi.csh`
		# -l "select=24:ncpus=8:mpiprocs=8+40:ncpus=8:mpiprocs=8:mem=109gb" ${SCRIPT_DIR}/run_jedi.csh`
     #${SCRIPT_DIR}/run_jedi.csh
   endif

   if ( $RUN_MPAS_DETERMINISTIC == true ) then
      setenv RUN_STAGE          $run_det_for
      setenv MPAS_STAGE         deterministic  # (ensemble,deterministic)
      setenv MPAS_INPUT_SOURCE  $MPAS_INPUT_SOURCE_DET
      set dependency_condition = ""
      if ( $RUN_JEDI_EnVar == true ) then
	 set dependency_condition = "-W depend=afterok:${id_envar}"
      endif
      if ( $RUN_STAGE == forecast && ( $num_mpas_cells_deterministic != $num_mpas_cells_free_fcst) ) then
	 set num_needed_nodes = `echo "$mpas_num_procs_free_fcst / $mpas_num_procs_per_node" | bc`
      else
	 set num_needed_nodes = `echo "$mpas_num_procs / $mpas_num_procs_per_node" | bc`
      endif
      set id_fcst = `qsub -N "mpas_det_${DATE}" -A "$mpas_account" -q $mpas_queue $dependency_condition \
		  -l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${mpas_num_procs_per_node}" \
		  -l walltime=${mpas_walltime}:00 -l job_priority=${mpas_priority} ${SCRIPT_DIR}/run_mpas.csh`
     #${SCRIPT_DIR}/run_mpas.csh
   endif

   if ( $RUN_MPAS_ENS == true ) then
      setenv RUN_STAGE           $run_ens_for
      setenv MPAS_STAGE          ensemble   # (ensemble,deterministic)
      setenv MPAS_INPUT_SOURCE   $MPAS_INPUT_SOURCE_ENS
      set dependency_condition = ""
      if ( $RUN_JEDI_ENKF == true ) then
	 set dependency_condition = "-W depend=afterok:${id_enkf}"
      endif
      if ( $RUN_STAGE == forecast && ( $num_mpas_cells_ens != $num_mpas_cells_free_fcst) ) then
	 set num_needed_nodes = `echo "$mpas_num_procs_free_fcst / $mpas_num_procs_per_node" | bc`
      else
	 set num_needed_nodes = `echo "$mpas_num_procs / $mpas_num_procs_per_node" | bc`
      endif
      if ( $RUN_STAGE == next_cycle || \
         ( $RUN_STAGE == forecast && ($num_members_to_run == $ENS_SIZE )) ) then
	 set id_fcst = `qsub -N "mpas_ens_${DATE}" -A "$mpas_account" -J ${ie}-${ENS_SIZE} -q $mpas_queue \
		  -l job_priority=${mpas_priority} $dependency_condition \
		  -l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${mpas_num_procs_per_node}" \
		  -l walltime=${mpas_walltime}:00 ${SCRIPT_DIR}/run_mpas.csh`
      else # Run MPAS for random members...NCL code selects the random members
         # get the random members and then submit one-at-a-time
         ncl $rand_num_script ENS_SIZE=$ENS_SIZE starting_seed=$DATE num_members_to_run=$num_members_to_run #Output is ./rand.txt
         set mems_to_run = `cat ./rand.txt`
	 foreach this_mem ( $mems_to_run )
            set mm1 = `expr $this_mem + 1`
	    qsub -N "run_mpas_${DATE}" -A "$mpas_account" -J "${this_mem}-${mm1}:2" \
		 -l "select=${num_needed_nodes}:ncpus=${num_procs_per_node}:mpiprocs=${mpas_num_procs_per_node}" \
		 -l walltime=${mpas_walltime}:00 ${SCRIPT_DIR}/run_mpas.csh
		#-W depend=afterok:${id_init}
	 end
      endif
     # ${SCRIPT_DIR}/run_mpas.csh 1
   endif

   setenv DATE `$TOOL_DIR/da_advance_time.exe $DATE ${CYCLE_PERIOD}m -f ccyymmddhhnn` #advance date

end

#Submit for next cycle; in this case, in above time control set:
# setenv start_init $start_init, specify start_init in the shell, and ./driver.csh
if ( $DATE <= $LAST_DATE && ( $start_init == $end_init ) ) then
  setenv start_init $DATE
  if ( $?id_fcst ) then
     qsub -W depend=afterany:${id_fcst} $myname
  endif
endif

exit 0
