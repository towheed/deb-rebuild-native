# deb-rebuild-native

CAUTION: This script has only been tested on Debian Stretch. It is not guaranteed to work on previous versions or derivatives of Debian.

Rebuild Debian packages using GCC -march=native option

NOTE: If you use this script to build a multitude of packages at once,
      especially if you pass the -d option, ensure you have ample free
      disk space available.

All build, status and log files are under $HOME/rebuild-native.

## Usage
This BASH script must be run with root privileges. The --preserve-environment
option MUST be passed to the gain-root-command used.

### Using su:
	su -p -c "script"
### Using sudo:
	sudo -E script
To run the script, issue the command (using su or sudo):

	./path/to/script/rebuild-native.sh [options] ... command [pkg1] [pkg2] ...
### Help
Help is available by passing the -h or --help option (using the gain-root-command):

	./path/to/script/rebuild-native.sh -h, or
	./path/to/script/rebuild-native.sh --help

### Description of Options

	-h, --help			Show help message
	-V, --version			Show version information
	
	-a, --march=cpu-type		This option tells the build system the CPU type to build for.
					This defaults to 'native' and should be adequate for most systems.
					For a list of CPU types recognized by GCC, please see
					https://gcc.gnu.org/onlinedocs/gcc-6.4.0/gcc/x86-Options.html#x86-Options
							
	-t --mtune=cpu-type		This option tells the build system to tune the build for the
					given CPU type. Please see https://gcc.gnu.org/onlinedocs/gcc-6.4.0/gcc/x86-Options.html#x86-Options
	
	-o, --optimize-level=num	Same as GCC's -O option. Do not use this unless you are sure you know what
					this is all about. Careless use of this option WILL cause massive breakages
					in your system.
	
	-s, --silent			Pass -s option to make. This suppresses all of GCC's output except for
					warnings and errors.
					
	-d, --dependencies		Passing this option, will also cause the build system to build all dependent
					packages also. This has the potential to increase the number of built packages
					greatly.
	
	-k, --keep-source		Pass this option if you want to keep the downloaded source files.
					All source files are removed by default after the build process completes.
	
	-b, --build-dbgsym		Pass this option if you want to build the dbgsym packages also.
					You do not need this unless you intend to debug and require the debug symbols.
					If you do not know what this is all about, you do not need the dbgsym packages.
	
	-c, --run-checks		Run tests provided by the package build during the build process.
	
	-v, --verbose			Show what is being done. All output are shown by default.
	
	-r, --target-release=release	Pass this option to tell the build system, which Debian release you are building for.
	
	-n, --name="full-name"		This is the full name of the user and is used for the changelogs. This MUST be
					quoted. Defaults to the author's full name.
	
	-e, --email=user-email		This the e-mail address of the user and is also used for the changelogs.
					Defaults to the authors e-mail address.
	

### Description of commands

	install [pkg1] [pkg2] ...	Rebuild and install the given packages. The package names must be valid Debian
					package names. This is checked by the script before any further processing takes
					place.
	
	upgrade				Rebuild all upgradeable packages, if any. For a list of upgradeable packages,
					issue the command: apt-get -s upgrade
	
	world				Rebuild all installed packages. Note that this option will consume a lot of disk
					space and can take days depending on the system and number of packages. This
					command may be issued at any time to check that all packages are actually built.
					Packages that have already been built, will not be rebuilt.
	
	repair				Repair the system if a crash occurred before the last invocation of the script
					completed. This will attempt to restore the system to it's previous state.

###### Note on rebuilding *world*: I'll highly recommend that you rebuild world in a containerized or chrooted system.

### Logging
All output from the script is logged. All logfiles are compressed with gzip. All logfile are kept in $HOME/rebuild-native/log. The main log (aptly named main.log.gz) log all output from the script, with the exception of the build output from the package builds. The build output are logged to src_name-src_version.log.gz, where src_name is the name of the source package built and the src_version is the version of the source package. Note though that the source names and version may not necessarily be similar in any way to the binary (.deb) packages built by them.

To view a log file, eg main.log.gz, issue the command:

	gunzip -c $HOME/rebuild-native/log/main.log.gz | less

#### Other files
A list of failed builds is kept in $HOME/rebuild-native/build.fail

The list of installed build dependencies is kept in $HOME/rebuild-native/build.depend. Any build dependencies installed by the scripts are removed when the build process completes.

The list of packages marked as 'install' before the build started is kept in $HOME/rebuild-native/install-list-before.list.

The list of packages marked as 'deinstall' before the build started is kept in $HOME/rebuild-native/deinstall-list-before.list.


### Emergency repair
If a crash occurred before a previous invocation of the script completed, an attempt can be made to recover the system by passing the 'repair' command to the script:

	./path/to/rebuild-native.sh repair

The success of the repair depends on the existence of 3 files in $HOME/rebuild-native:

	build.depend - List of build dependencies installed during the build process
	install-list-before.list - List of packages marked as 'install' before the build process started
	deinstall-list-before.list - List of packages marked as 'deinstall' before the build process started

The first two files must exists or the repair command fails.

#### Check if the repair command succeeded
The repair command will indicate 'success' of 'fail' upon completion. A failure indication does not necessarily mean that the system is unusable, but simply that some packages may not have been re-installed and/or purged. You can check the level of success using the following commands:

##### Check the logfile
You can view the repair logs:

	gunzip -c $HOME/rebuild-native/repair.log.gz | less

or check the status of the packages on the system:

	dpkg --get-selections | grep -w 'install$' | wc -l
	wc -l $HOME/rebuild-native/install-list-before.list

The first command will return the total number of packages currently marked as 'install' while the second will return the total number of packages that were marked as 'install' before the build process started. The aim of the repair command is to have these two numbers the same. If for some reason, the number of packages currently marked as 'install' is less, you can attempt to manually re-install those packages.

##### Purge removed packages
The repair command will attempt to purge all removed packages ie: remove their configuration files. All purged packages will be completely removed from the list of packages returned by:

	dpkg --get-selections

Any removed (not purged) packages will be marked as 'deinstall'. If you do not want the configuration files of these packages on your system you can manually purge those packages.


## Issues/BUGS

