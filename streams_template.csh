#!/bin/csh
#-----------------------------------------------------------------------
# This script fills "streams" files for various MPAS applications
#-----------------------------------------------------------------------
#
# Need to specify defaults for variables defined in scripts other than the driver
#
if ( ! $?restart_type        )   set restart_type = "input;output"
if ( ! $?update_sst_interval )   set update_sst_interval    = "none"
if ( ! $?lbc_output_interval )   set lbc_output_interval    = "none"
#if ( ! $?lbc_date            )   set lbc_date    = `${TOOL_DIR}/da_advance_time.exe $DATE 0 -f ccyy-mm-dd_hh:nn:ss`

#####

if ( $MPAS_REGIONAL =~ *true* || $MPAS_REGIONAL =~ *TRUE* ) then
   set lbc_input_interval = ${LBC_FREQ}:00:00 # $LBC_FREQ in hours
else
   set lbc_input_interval = none
endif

# Only output 1 of mpasout (da_state stream) files or restart files
#  No need to output both.  Depends on whether there is 2-stream IO
# Units are minutes
if ( $file_type == "mpasout" ) then # only output mpasout files
   set my_mpasout_output_interval = $restart_output_interval 
   set my_restart_output_interval = 9999999
else if ( $file_type == "restart" ) then # only output restart files
   set my_mpasout_output_interval = 9999999
   set my_restart_output_interval = $restart_output_interval
endif

# For some reason, when using array syntax, the output files written
# by this script aren't in the correct directory. So pass-in the proper
# directory and cd to it.
set rundir = $2
cd $rundir

echo "Filling streams for $1"

if ( $1 == "mpas" || $1 == "MPAS" ) then
   goto MPAS
else if ( $1 == "mpas_init" || $1 == "MPAS_init" ) then
   goto MPAS_init
else if ( $1 == "mpas_jedi" || $1 == "MPAS_JEDI" ) then
   goto mpas_jedi
echo "wrong usage"
   echo "use as $0 (mpas,mpas_init,mpas_jedi)"
   exit
endif

#--------------------------------------------
# MPAS_initialization streams.init_atmosphere
#--------------------------------------------

MPAS_init:

rm -f ./streams.init_atmosphere
cat > ./streams.init_atmosphere << EOF
<streams>
<immutable_stream name="input"
                  type="input"
                  filename_template="${config_input_name}"
                  input_interval="initial_only" />

<immutable_stream name="output"
        type="output"
        io_type="pnetcdf,cdf5"
        filename_template="${config_output_name}"
        clobber_mode="replace_files"
	precision="single"
        packages="initial_conds"
        output_interval="initial_only" />

<immutable_stream name="surface"
                  type="output"
		  io_type="pnetcdf,cdf5"
                  filename_template="./sfc_update.nc"
                  clobber_mode="replace_files"
	          precision="single"
                  packages="sfc_update"
                  filename_interval="none"
                  output_interval="24:00:00"/>

<immutable_stream name="lbc"
                  type="output"
	          precision="single"
		  io_type="pnetcdf,cdf5"
                  filename_template="lbcAllTimes.nc"
		  clobber_mode="replace_files"
                  packages="lbcs"
                  filename_interval="none"
                  output_interval="${lbc_output_interval}" />

</streams>
EOF
# possible LBC settings
#filename_template="lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
#filename_interval="output_interval"

exit 0

#--------------------------------------------
# MPAS streams.atmosphere
#--------------------------------------------

MPAS:

rm -f ./streams.atmosphere
cat > ./streams.atmosphere << EOF2
<streams>
<immutable_stream name="invariant"
                  type="input"
		  precision="single"
                  filename_template="./invariant.nc"
		  io_type="pnetcdf,cdf5"
                  input_interval="initial_only" />

<immutable_stream name="input"
                  type="input"
		  precision="single"
                  filename_template="./init.nc"
		  io_type="pnetcdf,cdf5"
                  input_interval="initial_only"/>

<immutable_stream name="restart"
        type="${restart_type}"
	precision="single"
        filename_template="restart.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
        io_type="pnetcdf,cdf5"
        input_interval="initial_only"
        clobber_mode="replace_files"
        output_interval="${my_restart_output_interval}:00" />

<immutable_stream name="da_state"
        type="output"
	precision="single"
        filename_template="mpasout.nc"
        io_type="pnetcdf,cdf5"
	packages="jedi_da"
        clobber_mode="replace_files"
        output_interval="none" />

<stream name="da_state_new"
        type="output"
        precision="single"
        filename_template="mpasout.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
        io_type="pnetcdf,cdf5"
        clobber_mode="replace_files"
        output_interval="${my_mpasout_output_interval}:00" >

        <stream name="da_state" />
        <var name="refl10cm" />
</stream>

<stream name="output"
        type="output"
	precision="single"
        filename_template="./output.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
        io_type="pnetcdf,cdf5"
        clobber_mode="replace_files"
        output_interval="none">

    <file name="${SCRIPT_DIR}/stream_list.atmosphere.output"/>
</stream>

<stream name="diagnostics"
        type="output"
	precision="single"
        filename_template="diag.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
	io_type="pnetcdf,cdf5"
        clobber_mode="replace_files"
        output_interval="00:${diag_output_interval}:00">

    <file name="${SCRIPT_DIR}/stream_list.atmosphere.diagnostics"/>
</stream>

<stream name="surface"
        type="input"
	precision="single"
        filename_template="./sfc_update.nc"
        io_type="pnetcdf,cdf5"
        filename_interval="none"
        input_interval="$update_sst_interval">
    <file name="${SCRIPT_DIR}/stream_list.atmosphere.surface"/>
</stream>

<immutable_stream name="lbc_in"
	 type="input"
	 precision="single"
	 filename_template="lbcAllTimes.nc"
	 io_type="pnetcdf,cdf5"
	 filename_interval="none"
	 packages="limited_area"
	 input_interval="${lbc_input_interval}" />

</streams>
EOF2
# possible LBC settings for MPAS v8.3.0+
#filename_template="lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
#filename_interval="input_interval"
#reference_time="${lbc_date}"
#####reference_time="2014-01-01_00:00:00"

exit 0

#--------------------------------------------
# MPAS-JEDI APPLICATIONS
#--------------------------------------------

mpas_jedi:

rm -f ./streams.atmosphere
cat > ./streams.atmosphere << EOF3
<streams>
<immutable_stream name="invariant"
                  type="input"
		  precision="single"
                  filename_template="${input_invariant_file}"
                  io_type="pnetcdf,cdf5"
                  input_interval="initial_only" />

<immutable_stream name="input"
                  type="input"
		  precision="single"
                  filename_template="${input_file}"
                  io_type="pnetcdf,cdf5"
                  input_interval="initial_only" />

<immutable_stream name="da_state"
                  type="output"
		  precision="single"
                  filename_template="mpasout.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  io_type="pnetcdf,cdf5"
		  packages="jedi_da"
                  clobber_mode="overwrite"
                  output_interval="none" />

<immutable_stream name="lbc_in"
                  type="input"
                  precision="single"
		  io_type="pnetcdf,cdf5"
                  filename_template="lbc.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="input_interval"
		  packages="limited_area"
                  input_interval="${lbc_input_interval}" />

<immutable_stream name="iau"
                  type="none"
                  filename_template="x1.62691.AmB.\$Y-\$M-\$D_\$h.\$m.\$s.nc"
                  filename_interval="none"
                  packages="iau"
                  input_interval="none" />

<stream name="background"
        type="input;output"
	precision="single"
	io_type="pnetcdf,cdf5"
        filename_template="background.nc"
        input_interval="none"
        output_interval="none"
        clobber_mode="overwrite">
        <file name="./stream_list.atmosphere.background"/>
</stream>

<stream name="analysis"
        type="output"
	precision="single"
	io_type="pnetcdf,cdf5"
        filename_template="analysis.nc"
        output_interval="none"
        clobber_mode="overwrite">
        <file name="./stream_list.atmosphere.analysis"/>
</stream>

<stream name="ensemble"
        type="input;output"
	precision="single"
	io_type="pnetcdf,cdf5"
        filename_template="ensemble.nc"
        input_interval="none"
        output_interval="none"
        clobber_mode="overwrite">
        <file name="./stream_list.atmosphere.ensemble"/>
</stream>

<stream name="control"
        type="input;output"
	precision="single"
	io_type="pnetcdf,cdf5"
        filename_template="control.nc"
        input_interval="none"
        output_interval="none"
        clobber_mode="overwrite">
        <file name="./stream_list.atmosphere.control"/>
</stream>

<stream name="output"
        type="none"
        filename_template="output.nc"
        output_interval="0_01:00:00" >
</stream>

<stream name="diagnostics"
        type="none"
        filename_template="diagnostics.nc"
        output_interval="0_01:00:00">
</stream>

</streams>
EOF3

exit 0

###
