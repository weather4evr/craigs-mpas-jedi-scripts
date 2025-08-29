#!/bin/csh
#PBS -S /bin/csh
#PBS -N init
#PBS -A NMMM0021
#PBS -l walltime=3:00   
#PBS -q preempt
#PBS -l job_priority=economy
#PBS -o init.out
#PBS -j oe 
#PBS -l select=16:ncpus=36:mpiprocs=36
#PBS -k eod 
#PBS -r y
#PBS -V 

# -------------------------------------
# This script runs MPAS initialization
# -------------------------------------
set DATE = $DATE # from driver.csh; ccyymmddhhnn (e.g., 202305231200)
set START_DATE_MPAS = `${TOOL_DIR}/da_advance_time.exe $DATE 0 -w`
set END_DATE_MPAS   = `${TOOL_DIR}/da_advance_time.exe $DATE ${FCST_RANGE}m -w` # Used for regional MPAS for LBCs
set sdate = `echo "$START_DATE_MPAS" | cut -c 1-13` # e.g., 2025-05-23_00

########
if ( $RUN_STAGE == deterministic ) then
   set UNGRIB_OUTPUT_DIR = ${UNGRIB_OUTPUT_DIR_DETERMINISTIC}/${DATE} # Where output of ungrib (input to here) is located
   set rundir = ${MPAS_INIT_DETERMINISTIC_OUTPUT_DIR_TOP}/${DATE}
   set mpas_static_data_file =  $mpas_static_data_file_deterministic
   set mpas_invariant_file =  $mpas_invariant_file_deterministic
   set GRID_FILE_NETCDF =     $grid_file_netcdf_deterministic
   set MPAS_GRID_INFO_DIR =   $grid_info_dir_deterministic
   setenv graph_info_prefx    $graph_info_prefx_deterministic
   setenv num_mpas_cells      $num_mpas_cells_deterministic

else if ( $RUN_STAGE == ensemble ) then
  #set mem = $1
   set mem = $PBS_ARRAY_INDEX #PBS with "-J" flag (PBS pro)

   set UNGRIB_OUTPUT_DIR = ${UNGRIB_OUTPUT_DIR_ENS}/${DATE}/ens_${mem} # Where output of ungrib (input to here) is located
   set rundir = ${MPAS_INIT_ENS_OUTPUT_DIR_TOP}/${DATE}/ens_${mem}
   set mpas_static_data_file =  $mpas_static_data_file_ens
   set mpas_invariant_file =  $mpas_invariant_file_ens
   set GRID_FILE_NETCDF =     $grid_file_netcdf_ens
   set MPAS_GRID_INFO_DIR =   $grid_info_dir_ens
   setenv graph_info_prefx    $graph_info_prefx_ens
   setenv num_mpas_cells      $num_mpas_cells_ens

else
   echo "RUN_STAGE = $RUN_STAGE is invalid.  Either (deterministic,ensemble). Exit."
   exit 1
endif

mkdir -p $rundir
cd $rundir
rm -f ./*.err # clean-up any error files from last time

# deal with the environment
ln -sf $mpas_environment_file . # keep to have a copy
source $mpas_environment_file

# init_atmosphere_model in mpas-bundle seems to be a little-endian compile, 
#  so unset the big endian variables we may have just sourced
#  if we didn't just source them, these lines won't hurt
unsetenv GFORTRAN_CONVERT_UNIT #'native;big_endian:101-200'
unsetenv F_UFMTENDIAN #'big:101-200'

# cd again to $rundir; under some strange conditions, probably a combination
# of job arrays on derecho, and possible use of 'pwd' in $mpas_environment_file
# (if $mpas_environment_file ==> jedi_environment), things can end up in the
# wrong directory. pretty strange, but just do it.
cd $rundir

if ( $mpas_compiled_within_jedi =~ *true* || $mpas_compiled_within_jedi =~ *TRUE* ) then
  #ln -sf ${MPAS_CODE_DIR}/build/mpas-bundle/bin/mpas_init_atmosphere ./init_atmosphere_model
   set exec = `find $MPAS_JEDI_BUNDLE_DIR -name mpas_init_atmosphere`
   ln -sf $exec[1] ./init_atmosphere_model
   set this_run_cmd = $run_cmd_jedi
  #setenv GFORTRAN_CONVERT_UNIT 'native;big_endian:101-200' # needed for gfortran compiler
  #setenv F_UFMTENDIAN 'big:101-200' # maybe needed for intel compiler
   if ( $?mpasjedi_library_path ) setenv LD_LIBRARY_PATH ${mpasjedi_library_path}:$LD_LIBRARY_PATH # need path of library on derecho
else
   ln -sf ${MPAS_CODE_DIR}/init_atmosphere_model .
   set this_run_cmd = $run_cmd
endif

ln -sf ${MPAS_GRID_INFO_DIR}/${graph_info_prefx}* .
if ( -e $vert_levels_file ) ln -sf $vert_levels_file . # just for record keeping. full path used in namelist

# First iteration  : Interpolate static data onto the domain--only need to do once per domain/mesh
# Second iteration : Interpolate SST update data onto the domain, if $update_sst = .true.
# Third  iteration : Interpolate meteorological data onto domain with proper number of vertical levels
# Fourth iteration : Make boundary conditions
foreach iter ( static_data  sst_data   met_data    met_data_lbcs )

   # Assume all init_atmosphere stages are .false. each time through loop
   # Set things to .true. as needed
   setenv config_static_interp   .false.
   setenv config_vertical_grid   .false.
   setenv config_met_interp      .false.
   setenv config_input_sst       .false.
   setenv config_frac_seaice     .false.
   setenv lbc_output_interval   "none"

   if ( $iter == static_data ) then

      if ( -e $mpas_static_data_file ) continue  # Only need to do this once per mesh

      setenv case_number   7
      setenv config_stop_time   $START_DATE_MPAS

      setenv config_static_interp   .true.

      setenv config_input_name    $GRID_FILE_NETCDF       # Full path, from driver.csh
      setenv config_output_name   `basename $mpas_static_data_file` # Relative path, from driver.csh

   else if ( $iter == sst_data ) then
      if ( $update_sst =~ *true* || $update_sst =~ *TRUE* ) then
	 if ( ! -e ${UNGRIB_OUTPUT_DIR}/${ungrib_prefx_sst}:${sdate} ) then
	    echo  "${UNGRIB_OUTPUT_DIR}/${ungrib_prefx_sst}:${sdate}" >> ./MISSING_FILE
	    continue
	 endif

	 ln -sf ${UNGRIB_OUTPUT_DIR}/${ungrib_prefx_sst}:${sdate} .

	 setenv case_number   8
	 setenv config_stop_time   $START_DATE_MPAS

	 setenv config_input_sst       .true.
	 setenv config_frac_seaice     .true.

	 ln -sf $mpas_static_data_file  ./static.nc
	 setenv config_input_name    "./static.nc"
	 setenv config_output_name   "./none"   # Output is really sfc_update.nc

      else
	 continue # go to next iteration
      endif

   else if ( $iter == met_data ) then

      if ( ! -e  ${UNGRIB_OUTPUT_DIR}/${ungrib_prefx_model}:${sdate} ) then
         echo   "${UNGRIB_OUTPUT_DIR}/${ungrib_prefx_model}:${sdate}" >> ./MISSING_FILE
         continue
      endif
      ln -sf ${UNGRIB_OUTPUT_DIR}/${ungrib_prefx_model}:${sdate} .

     #Get the number of levels in the ungrib file; 'VV' is a good variable to look at.
      ln -sf ${WPS_DIR}/util/rd_intermediate.exe .
      set num_levels = `./rd_intermediate.exe ./${ungrib_prefx_model}:${sdate} | grep VV | wc -l`
      setenv num_ungrib_vertical_levels  $num_levels

      setenv case_number   7
      setenv config_stop_time   $START_DATE_MPAS

      setenv config_vertical_grid   .true.
      setenv config_met_interp      .true.
      setenv config_frac_seaice     .true.

      ln -sf $mpas_static_data_file  ./static.nc
      setenv config_input_name    "./static.nc"
      setenv config_output_name   "./init.nc"

   else if ( $iter == met_data_lbcs ) then

      if ( $MPAS_REGIONAL =~ *true* || $MPAS_REGIONAL =~ *TRUE* ) then # only do this if regional

	 ln -sf ${UNGRIB_OUTPUT_DIR}/${ungrib_prefx_model}* .

	 setenv case_number   9
	 setenv config_stop_time   $END_DATE_MPAS

	 setenv config_input_name    ./init.nc  # use the initial conditions file as input
	 if ( ! -e $config_input_name ) then
	    echo "MPAS initialization failed for iteration ${iter}."
	    echo "The file $config_input_name is missing."
	    exit 1
	 endif
	 setenv config_output_name   "./none"
	 setenv lbc_output_interval  "${LBC_FREQ}:00:00"

      else
         continue # move on (b/c this is the last iteration, this will exit the loop)
      endif

   else
      echo "Iter = $iter is wrong.  Not a specified option.  Big bug somehwere.  Exit"
      exit 0
   endif

   # ---------------------------
   # Fill namelist and streams
   # ---------------------------
   $NAMELIST_TEMPLATE  mpas_init $rundir
   set namelist_file = namelist.init_atmosphere # Output of above command

   $STREAMS_TEMPLATE   mpas_init $rundir
   set stream_file = streams.init_atmosphere # Output of above command

   # -----------------------
   # Run MPAS initialization
   # -----------------------
   cd $rundir
   $this_run_cmd -n $mpas_init_num_procs -ppn $mpas_init_num_procs_per_node ./init_atmosphere_model # mpiexec -n 128 -ppn 128
   #$this_run_cmd ./init_atmosphere_model # this was used on Cheyenne

   # Error check
   if ( $status != 0 ) then
      echo "MPAS initialization failed for iteration ${iter}."
      exit 1
   endif

   # Make $mpas_static_data_file and $mpas_invariant_file
   if ( $iter == static_data ) then
      set dd = `dirname $mpas_static_data_file`  # Get directory where this file is located
      mkdir -p $dd # make sure the directory is there; it might not be at the very beginning
      mv $config_output_name $dd  # Once moved, this file is $mpas_static_data_file
      cp ./${namelist_file}  ${dd}/${namelist_file}_${iter}
      cp ./${stream_file}    ${dd}/${stream_file}_${iter}
   endif

   # the 'invariant.nc' file can simply be an init.nc file
   if ( $iter == met_data ) then
      if ( ! -e $mpas_invariant_file ) then
	 set dd = `dirname $mpas_invariant_file`  # Get directory where this file is located
	 mkdir -p $dd # make sure the directory is there; it might not be at the very beginning
	 cp $config_output_name $mpas_invariant_file  # Once moved, this file is $mpas_static_data_file
	#cp ./${namelist_file}  ${dd}/${namelist_file}_${iter}
	#cp ./${stream_file}    ${dd}/${stream_file}_${iter}
      endif
   endif

   # Cleanup
   if ( $iter == sst_data ) rm -f $config_output_name  # This file is created, even though we don't want it to be. It is the same as $mpas_static_data_file

   mv ./${namelist_file}  ./${namelist_file}_${iter}  # Save a namelist for each step
   mv ./${stream_file}    ./${stream_file}_${iter}  # Save a stream for each step
   mv ./log.init_atmosphere.0000.out ./log.init_atmosphere.0000.out_${iter}
   rm -f ./*.lock # These files could be there if there was a failure with a JEDI-compiled executable

end # Iter

exit 0
