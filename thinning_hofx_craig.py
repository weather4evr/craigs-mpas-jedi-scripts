import os, sys
import getopt
import numpy as np
import netCDF4 as nc4

#============================================================================

def calc_dimensions(ncin, ncout):
   # Calculate how many locations are not thinned.
   igroups = ncin.groups
   for grpname, group in igroups.items():
      if(grpname == "EffectiveQC0"):
         variables = list(group.variables.items())
         varname, qc_var = variables[0]
         if len(qc_var.shape) == 2:
            valid_indices = np.where(np.any(qc_var[:, 0:] == 0, axis=1))[0]
         else:
            qc_var_2d = []
            for varname, qc_var in variables:
               qc_var = np.expand_dims(qc_var, axis=1)
               qc_var_2d.append((varname, qc_var))
            qc_var = np.concatenate([var[1] for var in qc_var_2d], axis=1)
            valid_indices = np.where(np.any(qc_var[:, 0:] == 0, axis=1))[0]

   return valid_indices

#-----------------------------------------------------------------------------------------
def copy_attributes(ncin, ncout):
   inattrs = ncin.ncattrs()
   for attr in inattrs:
      if attr != '_FillValue':
         attr_value = ncin.getncattr(attr)
         if isinstance(attr_value, str):
            ncout.setncattr_string(attr, attr_value)
         else:
            ncout.setncattr(attr, attr_value)

#=========================================================================================

# set defaults
rundir = '.'
hofxfile = 'obsout_da_amsua_n19.h5'
outfile = 'new_obsout_da_amsua_n19.h5'

# get command line arguments
opts, args = getopt.getopt(sys.argv[1:], '', ['thinning=', 'rundir=', 'hofxfile=', 'outfile='])

for o, a in opts:
   if o in ('--thinning'):
      thinning = int(a)
   elif o in ('--rundir'):
      rundir = a
   elif o in ('--hofxfile'):
      hofxfile = a
   elif o in ('--outfile'):
      outfile = a
   else:
      print('o: <%s>' %(o))
      print('a: <%s>' %(a))
      assert False, 'unhandled option'

#--------------------------------------------------------------------------------

hofxfile = '%s/%s' %(rundir, hofxfile)
outfile  = '%s/%s' %(rundir, outfile)

print('hofxfile: %s' %(hofxfile))
print('outfile: %s'  %(outfile))

if(os.path.exists(outfile)): os.remove(outfile)

IFILE = nc4.Dataset(hofxfile, 'r') # input file
OFILE = nc4.Dataset(outfile, 'w', format='NETCDF4') # outputfile

# Determine number of thinned data
valid_indices = calc_dimensions(IFILE, OFILE) # figure out the number of points with appropriate QC
new_locs = len(valid_indices)
print('thinned data has size: %d\n' %(new_locs))

# create dimensions in the output file
for name, dimension in IFILE.dimensions.items():
   print('dimension: %s has size: %d' %(name, dimension.size))
   if (name == "Location" and thinning == 1):
      OFILE.createDimension(name, new_locs)
   else:
      OFILE.createDimension(name, dimension.size)

# copy global attributes from input to output file
copy_attributes(IFILE, OFILE)

comgrps = []
igroups = IFILE.groups
for grpname, group in igroups.items():
   if grpname in ["MetaData", "PreQC", "ObsError", "ObsValue", "ObsType"]:
      comgrps.append(grpname)

# copy groups. then for each group, create the variable and fill it.
#groups = list(IFILE.groups)
for group in comgrps:
   OFILE.createGroup(group)
   for name, variable in IFILE[group].variables.items():
      if name == 'stationIdentification': continue

      fvname = '_FillValue'
      if(fvname in variable.__dict__):
         fill_value = variable.getncattr(fvname)
         if isinstance(fill_value, np.int32):
            fill_value = 999999999
         elif isinstance(fill_value, np.float32):
            fill_value = 999999999.0
         newvar = OFILE[group].createVariable(name, variable.datatype, variable.dimensions, fill_value=fill_value)
      else:
         newvar = OFILE[group].createVariable(name, variable.datatype, variable.dimensions)

     # write file depending on dimension size
      if (newvar.shape[0] == new_locs and thinning == 1):
         if len(newvar.shape)   == 1: OFILE[group][name][:]     = IFILE[group][name][valid_indices]
         elif len(newvar.shape) == 2: OFILE[group][name][:,:]   = IFILE[group][name][valid_indices,:]
         elif len(newvar.shape) == 3: OFILE[group][name][:,:,:] = IFILE[group][name][valid_indices,:,:]
      else:
         if len(newvar.shape)   == 1: OFILE[group][name][:] = IFILE[group][name][:]
         elif len(newvar.shape) == 2: OFILE[group][name][:,:] = IFILE[group][name][:,:]
         elif len(newvar.shape) == 3: OFILE[group][name][:,:,:] = IFILE[group][name][:,:,:]

      # copy variable attributes all at once via dictionary
      #dst[group][name].setncatts(src[group][name].__dict__)
      copy_attributes(IFILE[group][name], OFILE[group][name])

# Copy variables not in groups
for name, variable in IFILE.variables.items():
   if name == 'stationIdentification': continue

   fvname = '_FillValue'
   if(fvname in variable.__dict__):
      fill_value = variable.getncattr(fvname)
      if isinstance(fill_value, np.int32):
         fill_value = 999999999
      elif isinstance(fill_value, np.float32):
         fill_value = 999999999.0
      newvar = OFILE.createVariable(name, variable.datatype, variable.dimensions, fill_value=fill_value)
   else:
      newvar = OFILE.createVariable(name, variable.datatype, variable.dimensions)

  # write file depending on dimension size
   if (newvar.shape[0] == new_locs and thinning == 1):
      if len(newvar.shape) == 1: OFILE[name][:] = IFILE[name][valid_indices]
      elif len(newvar.shape) == 2: OFILE[name][:,:] = IFILE[name][valid_indices,:]
      elif len(newvar.shape) == 3: OFILE[name][:,:,:] = IFILE[name][valid_indices,:,:]
   else:
      if len(newvar.shape)   == 1: OFILE[name][:] = IFILE[name][:]
      elif len(newvar.shape) == 2: OFILE[name][:,:] = IFILE[name][:,:]
      elif len(newvar.shape) == 3: OFILE[name][:,:,:] = IFILE[name][:,:,:]

   # copy variable attributes all at once via dictionary
   #dst[group][name].setncatts(src[group][name].__dict__)
   copy_attributes(IFILE[name], OFILE[name])

# close the files
IFILE.close()
OFILE.close()
print('Successfully generated thinned IODA files!')
