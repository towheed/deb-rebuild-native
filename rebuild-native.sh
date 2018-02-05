#! /bin/bash

export PS4='+$LINENO: $FUNCNAME: '

# Set tab=4

# (c) 2017, 2018 Towheed Mohammed <towheedm@yahoo.com>
#
#
# This package is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 dated June, 1991.
#
# This package is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this package; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
# 02111-1307, USA or visit https://www.gnu.org/licenses/gpl-2.0.html

# TODO Check BASH_VERSION=4.2+

# TODO Make all *_list vars arrays instead of strings

# TODO Ensure only one instance of this script is running

# Declare our vars
version="0.51.10-beta"									# Version information
app_name="rebuild-native"								# Name of application
march_opt="-march=native"								# gcc's march option
mtune_opt="-mtune=native"								# gcc's mtune option
optimize_opt="-O2"										# gcc's optimization level
silent_opt=false										# make's slient build option
depend_opt=false										# Build dependencies also. Do not build dependencies by default
keep_source_opt=false									# Keep downloaded source files
dbgsym_opt=false										# Keep dbgsym packages
checks_opt=false										# Run package tests during the build process
verbose_opt=false										# Be verbose. By default, some status messages are shown. If set, the output from
														# the external commands such as 'apt-get' are shown instead
release_opt=""											# Suite to search for available package
user=""													# Username of the invoking user

deb_name="Towheed Mohammed"								# Name to use for DEBFULLNAME
deb_email="towheedm@yahoo.com"							# Name to use for DEBEMAIL

packages_list=""										# List of packages
install_list=""											# List of packages marked as 'install'
hold_list=""											# List of packages mark as on 'hold'
broken_list=""											# List of broken packages
deinstall_list=""										# List of packages marked as 'deinstall'

source_list=""											# List of source packages
no_source_list=""										# List of packages we fail to get sources for
build_list=""											# List of packages to build
no_build_list=""										# List of packages excluded from building
build_fail_list=""										# List of packages that failed to build
pkg_src_map_list=""										# Binary package to source mapping list
fail_dl_list=""											# List of source packages that fail the download

apt_list=""												# List of packages return by get_apt_list
use_release=true

version_list=""											# List of packages and their versions

suffix="+native"										# Suffix for package version number

passwd_file="/etc/passwd"

main_dir="$HOME/$app_name"								# Main directory
build_dir="$main_dir/build"								# Build directory
backup_dir="$main_dir/backup"							# Backup directory
buildinfo_dir="$main_dir/buildinfo"						# Directory holding buildinfo files
log_dir="$main_dir/log"									# Log directory
tmp_dir="$main_dir/tmp"									# Temporary directory
repo_dir="/srv/local-apt-repository"					# Local repo directory

build_dep_fname="$HOME/$app_name/build.depend"			# List of build dependencies we installed
build_fail_fname="$HOME/$app_name/build.fail"			# List of packages that failed to build
main_log_fname="$log_dir/main.log"
repair_log_fname="$log_dir/repair.log"
install_list_fname="$main_dir/install-list-before.list"	# Our initial install_list
deinstall_list_fname="$main_dir/deinstall-list-before.list"	# Our initial deinstall_list

logfile_pid=""											# PID of the logfile process

show_help() {
	# Show help message and exit
	# We show why we bail from the parser by parsing an error
	# message as the first parameter
	
	# TODO Add retry command to retry failed builds
	# TODO Add simulate option

	[[ -n $1 ]] && echo -e "$1\n"
	cat <<-END_HELP
		$app_name v$version - Fetch sources and build packages optimized for your architecture.
		
		Usage: su -p -c "$app_name [OPTION]... COMMAND [pkg1] [pkg2]..."
		       sudo -E $app_name [OPTION]... COMMAND [pkg1] [pkg2]...

		Mandatory arguments to long options are mandatory for short options too.
		[OPTIONS]
		-h, --help                                - Show this help message and exit
		-V, --version                             - Show version information and exit
		
		-a, --march=cpu-type                      - Build the package(s) for the given CPU type
		                                            If not given, defaults to 'native'
		                                            See the GCC manual for more information
		-t, --mtune=cpu-type                      - Tune the package(s) build for the given CPU type
		                                            If not given, defaults to CPU type for --march
		                                            Must be given after --march option
		                                            See the GCC manual for more information
		-o, --optimize-level=num                  - Same as GCC -O option (UMIMPLEMENTED)
		                                            Use ONLY if you know what you are doing

		-s, --silent                              - Pass -s option to 'make'
		-d, --dependencies                        - Build dependencies also
		-k, --keep-source                         - Keep downloaded source files
		-b, --build-dbgsym                        - Build dbgsym packages also
		                                            Defaults to not building
		-c, --run-checks                          - Run tests during package build
		                                            Defaults to skipping the package tests
		-v, --verbose                             - Show what is being done (UNIMPLEMENTED)

		-r, --target-release=release              - Specify the target release. (UNIMPLEMENTED)
		                                            Same as 'apt-get' -t option. See 'man(8) apt-get'

		-n, --name=full-name                      - User's full name. Must be quoted
		                                            This name is used for the changelogs
		                                            Defaults to the author's name
		-e, --email=user-email                    - User's e-mail address
		                                            This e-mail is used for the changelogs
		                                            Defaults to the author's e-mail address

		[COMMANDS]
		install pkg1 [pkg2 ...]                   - Rebuild and install packages
		upgrade                                   - Rebuild and upgrade all upgradeable package(s)
		world                                     - Rebuild the world (all installed packages)
		                                            This may take days depending on the number of packages
		retry                                     - Retry all failed builds (UNIMPLEMENTED)
		repair                                    - Repair the system if a crashed occurred before the
		                                            last invocation of the script completed

END_HELP
	exit 0
}

bail_out() {
	# Display a message and bail with status 1
	# TODO Put msgs in a sparse array with index equal to exit status

	echo -e "$1"
	exit 1

}

get_confirmation() {
	# Get the user's confirmation before completing some action
	# Return status:
	# 0 - Yes
	# 1 - No

	# TODO Let caller pass prompt to display
	sleep 1											# Needed because of start_logfile function
	while true; do
		read -p "Continue (y/n):"
		case $REPLY in
			y|Y)
				return 0
			;;
			*)
				return 1
			;;
		esac
	done

}

set_spaces() {
	# Returns the global variable spc set to
	# the number of spaces specified by $1
	
	spc=""
	for (( i=1 ; i<=$1 ; i+=1 )); do
		spc="$spc "
	done

}

start_logfile() {
	# Start the main logfile

	# Lifted from Wooledge Bash FAQ #106
	# Thanks Wooledge

	# TODO Needs refining
	# TODO Acknowledge XON/XOFF when sent from kybd

	trap "rm -f $tmp_dir/pipe$$; gzip -f $1; exit" EXIT
	[[ ! -p $tmp_dir/pipe$$ ]] && mkfifo "$tmp_dir"/pipe$$
	tee -a "$1" < "$tmp_dir"/pipe$$ &
	logfile_pid=$!										# Save PID of background 'tee' process
	exec 6>&1											# Save stdout to FD 6
	exec > "$tmp_dir"/pipe$$							# Redirect stdout to pipe

	sleep 1												# Wait, or prompt for get_confirmation is desynchronized
}

stop_logfile() {
	# Stop the main logfile

	# TODO Needs refining

	kill -TERM $logfile_pid								# Send SIGTERM to background 'tee' process
	wait $logfile_pid									# Wait for process to finish
	exec 1>&6 6>&-										# Restore stdout and close FD 6

}

get_apt_list() {
	# Get various lists of packages using apt-get
	# apt-get command is passed in via $1 and the list is returned
	# via a global variable 'apt_list'
	# To retrieve the list, we filter the packages listed by apt-get
	# between a 'begin' and 'end' lines
	# Eg: 'apt-get upgrade ' returns:
	#      ... Various multi-line messages ...
	#      The following packages will be upgraded:
	#      ... Multi-line lists of packages with each line preceded by 2 spaces
	#      ... Various other multi-line messages
	#
	#      To retrieve the list, we filter everything between
	#      The following packages will be upgraded: and the first line not
	#      starting with a space. The list is then processed and returned to the caller

	# Parameters: $1 - command (required)
	#             $2 - a single packagename (optional)
	#             $3 - release (optional)

	local begin
	local release
	local apt_cmd

	case $1 in
		upgrade)
		apt_cmd="$1"
		begin="The following packages will be upgraded:"
		;;
		build-dep)
		apt_cmd="--ignore-hold build-dep"						# Ignore held packages to satisfy build dependencies
		begin="The following NEW packages will be installed:"
		;;
	esac

	# This is specific to APT's build-dep command
	# Try to get retrieve the list of build dependencies
	# from the same repo as the source package. If that
	# fails, let APT decide. This can happen depending on
	# how the repo is setup, and happens with both the
	# local and backports repo
	[[ -n $3 ]] && release="-t $3"
	apt_list=$(apt-get -s $release $apt_cmd $2)
	if [[ $? = "100" ]]; then
		use_release=false
		apt_list=$(apt-get -s $apt_cmd $2)
		[[ $? = "100" ]] && return 100							# If it still fails return
	fi

	# Get list of packages using a multi-line sed command
	# This MUST be a multi-line command or the sed command fails
	apt_list=$(sed -n '
					/'"$begin"'/,/^[^ ]/ {
						/'"$begin"'/n
						/^[^ ]/ !{
							p
						}
					}
				   ' <<< "$apt_list" | sed 's,^  ,,g' | tr ' ' '\n')

	return 0

}

get_package_version() {
	# Get the version and target release of packages
	# Positional parameters:
	# - $1 Version to retrieve
	#      i=installed version
	#      c=candidate version
	# - $2 List of packages

	local version
	local release
	local count
	local num_pkg
	local policy
	local priority
	local src_priority
	local v_list
	local x
	local l
	local apt_cache
	local msg
	local p_list
	local y

	if [[ $1 = "i" ]]; then
		msg="installed"
		y="Installed:"
	else
		msg="candidate"
		y="Candidate:"
	fi

	tmp=
	p_list=($2)																	# Put list of packages into an array
	x="Version table:"
	let count=1
	num_pkg="${#p_list[@]}"
	apt_cache=$(apt-cache policy ${p_list[@]})									# Get APT policy for all packages
	src_priority=$(apt-cache policy)											# Get list of sources and their priorities
	for pkg in ${p_list[@]}; do
		echo "($count/$num_pkg) Getting $msg version for $pkg:"
		# We let APT tell us the version of the package to get by selecting
		# the 'Candidate' version
		policy=$(sed -n "/^${pkg%:*}:$/,/^[^ ]/ p" <<< "$apt_cache")
		while read -r line; do
			case $line in
				*${y}*)
					version=${line#${y} }									# Get candidate version
					# Some packages such as virtual packages will not return a version
					# Any packages providing these 'virtual' or other such packages should
					# already be in the list. We do not need to save them. These packages
					# will be removed from the list by the sanitize_build_list function
					[[ $version = "(none)" ]] && continue 2
				;;
				*${x})
					v_list=${policy#*Version table:}							# Get list of versions and their priorities
					priority=
					while read -r line; do
						if [[ $line = *$version* ]]; then
							priority=${line##* }								# Get priority for this version
							priority="$priority "
						elif [[ -n $priority && $line = *${priority}* ]]; then
							# Iterate thru the list of source priorities to find this
							# source priority
							while read -r src_line; do
								if [[ $src_line = $line ]]; then
									read -r src_line							# Get next line from source priority
									if [[ $src_line = *n=* ]]; then
										release=${src_line#*n=}
										release=${release%%,*}
									else
										release="unknown"
									fi
									break 3
								fi
							done <<< "$src_priority"
						fi
					done <<< "$v_list"
				;;
			esac
		done <<< "$policy"

		let l=${#count}+${#num_pkg}+3											# Num spaces is 3 greater than length of count+num_pkg
		set_spaces $l
		# TODO Use printf instead?
		echo "$spc   Selecting $pkg=$version from $release"
		tmp="$tmp$pkg=$version/$release "
		let count+=1
	done
	version_list=$(tr ' ' '\n' <<< "$tmp")

}

fetch_source() {
	# Get sources for packages to build
	# Download and unpack sources in the build directory. We do not verify
	# the checksums of the downloaded files as this is done by apt-get

	local src_version
	local release
	local nv_list
	local r_cnt

	tmp=
	cd "$build_dir"
	for pkg in $build_list; do
		# Check that we can download all sources first
		# We extract the package's source name from the info
		# returned by 'apt-get -s source ...'
		echo -e "\nChecking that we can download source package for $pkg:"
		release=${pkg#*/}												# Get release
		version=${pkg#*=}
		version=${version%/*}											# Get version
		pkg=${pkg%=*}													# Get name of package
		tmp=$(apt-get -q0 -s -t $release source $pkg=$version 2>&1)
		if [[ $? = "100" ]]; then
			echo "  Unable to find a source package for $pkg=$version/$release...not building"
			no_source_list="$no_source_list$pkg=$version/$release "
			no_build_list="$no_build_list$pkg=$version/$release "		# Add to list of packages excluded from building
			continue
		fi
		tmp=${tmp##* }													# Get name of source package
		# Remove gcc and linux kernel source packages
		# and skip sources already in the list
		if [[ $tmp = gcc-* ]]; then
			echo "  Found source package '$tmp'. This is a GCC source package, not fetching"
			no_build_list="$no_build_list$pkg=$version/$release "		# Add to list of packages excluded from building
			continue
		elif [[ $tmp = "linux" ]]; then
			echo "  Found source package '$tmp'. This is a Linux kernel source package, not fetching"
			no_build_list="$no_build_list$pkg=$version/$release "		# Add to list of packages excluded from building
			continue
		# This script is not intended to build multiple versions of
		# the same source package. The following breaks if that changes
		elif [[ $source_list = *$tmp=* ]]; then
			echo "  Source package $tmp already downloaded"
			# Leading space for first source needed for build_package function
			#----------------------------------v-------------
			pkg_src_map_list="$pkg_src_map_list $pkg=$tmp "				# Map binary package to it's source package
		else
			echo "  Found source package '$tmp', fetching..."
			let r_cnt=0
			while true; do
				# We download all sources as a regular user to
				# prevent the 'unsandboxed' warning for some sources
				su $user -c "apt-get -q0 -y -t $release source $pkg=$version" 2>&1 && break
				if (( $r_cnt == 2 )); then
					echo -e "\nFailed to download source package $tmp 3 times...not retrying anymore"
					fail_dl_list="$fail_dl_list$tmp "					# Add the source package to the failed-to-download list
					continue 2
				else
					echo -e "\nFailed to download source package $tmp...retrying"
					let r_cnt+=1
				fi
			done

			# Ditto as per the comments above for multiple versions
			# Get the version of the source package from the .dsc file
			# Ensure version is within the Source stanza
			src_version=$(sed -n '/^[[:blank:]]*Source:/,/^[[:blank:]]*Version:/ s,^[[:blank:]]*Version:[[:blank:]]*,,p' "$tmp"_*.dsc)

			# Do not build any source for which we cannot get it's version
			if [[ -z $src_version ]]; then
				echo "Failed to get version for source package $tmp...not building" | tee -a "$build_fail_fname"
				nv_list="$nv_list$pkg@$tmp "
				no_build_list="$no_build_list$pkg=$version/$release "	# Add to list of packages excluded from building
			else
				# Leading space for first source needed for build_package function
				#------------------------v-----------------------
				source_list="$source_list $tmp=$src_version/$release"
				# Leading space for first package needed for build_package function
				#----------------------------------v-------------
				pkg_src_map_list="$pkg_src_map_list $pkg=$tmp "			# Map binary package to it's source package
			fi
		fi
	done

	# Remove all source files for which we did not get the version
	if [[ -n $nv_list ]]; then
		echo "Unable to get version for the following sources (removing all source files):"
		for pkg in $nv_list; do
			tmp=${pkg#*@}
			echo "  $tmp - source package for ${pkg%@*}"
			rm -rf "$tmp-"*												# Remove source directory
			rm -f "$tmp_"*												# Remove other source files
		done
	fi

}

get_build_depends() {
	# Get the list of build dependencies for the source
	# that we are about to build
	# We pass these positional parameters:
	# - $1: binary package built by the source package
	# - $2: version of the binary package
	# - $3: Release of the binary package

	# Get list of build dependencies and return if we succeeded
	get_apt_list build-dep "$1=$2" "$3" && return

	# APT 'build-dep' command does not resolve all build dependency conflicts
	# If this is the case because the above call to get_apt_list fails, then
	# remove all previously installed build dependencies and retry
	apt-get -y remove $(tr '\n' ' ' < "$build_dep_fname") 2>&1			# Remove previously installed build dependencies
	true > "$build_dep_fname"											# Clear the contents of build.depend
	get_apt_list build-dep "$1=$2" "$3"									# Retry

	# At this point, we should have satisfied the build dependencies
	# If not, then it may be because we have packages on hold, or
	# previously installed conflicting packages
	return $?

}

build_package() {
	# Now we start the re-build process

	# TODO Only build packages from source_list. Do not traverse
	#      the entire build dir

	local src													# Name of source package
	local version												# Version of source package
	local log_file												# Log file for build output
	local release
	local use_release
	local bin_pkg
	local bin_version
	local bin_release
	local old_PWD
	
	# Set these environment variables
	export DEBFULLNAME="$deb_name"
	export DEBEMAIL="$deb_email"
	export DEB_CFLAGS_APPEND="$march_opt $mtune_opt"
	export DEB_CXXFLAGS_APPEND="$DEB_CFLAGS_APPEND"
	export DEB_OBJCFLAGS_APPEND="$DEB_CFLAGS_APPEND"
	export DEB_OBJCXXFLAGS_APPEND="$DEB_CXXFLAGS_APPEND"
	$checks_opt || export DEB_BUILD_OPTIONS="nocheck "
	$dbgsym_opt || export DEB_BUILD_OPTIONS+="noddebs"
	$silent_opt && export MAKEFLAGS="-s"

	# Iterate over the directories in $build_dir and extract the source
	# name from the control file and the version and release from
	# source_list. We then install the build dependencies for this
	# source and it's corresponding version and release

	old_PWD=$PWD
	for src_dir in $build_dir/*; do
		[[ ! -d $src_dir ]] && continue
		cd $src_dir
		src=$(grep '^[[:blank:]]*Source:' debian/control)		# Get Source field
		src=${src##* }											# Get source name
		tmp=${source_list#* $src=}								# Extract version and release
		tmp=${tmp%% *}											# of src pkg from source_list
		version=${tmp%/*}										# Get version of source package
		release=${tmp#*/}										# Get release of source package

		echo -e "\nGetting build dependencies for $src=$version from $release:" | tee -a "$main_log_fname"

		# We retrieve the build dependencies for a binary package and not
		# a source package. We first find as binary package built by this
		# source package and get the build dependencies for it. All binary
		# packages built by this source package will have the same
		# version and build dependencies. It does not matter which binary
		# package we choose
		bin_pkg=${pkg_src_map_list%=$src *}						# Find a binary package built
		bin_pkg=${bin_pkg##* }									# by this source package
		tmp=$(grep "^$bin_pkg=" <<< "$build_list")				# Extract version and release
		tmp=${tmp#*$bin_pkg=}									# from build_list
		bin_version=${tmp%/*}									# Get version of binary package
		bin_release=${tmp#*/}									# Get release of binary package

		get_build_depends "$bin_pkg" "$bin_version" "$bin_release"	# Get list of build dependencies

		if [[ $? = "0" ]]; then
			if [[ -z $apt_list ]]; then
				echo "  All build dependencies met" | tee -a "$main_log_fname"
			else
				for pkg in $apt_list; do
					echo "  $pkg"								# Save build-dependencies
				done | tee -a "$build_dep_fname" "$main_log_fname"

				# We now install/remove packages to satisfy the build dependencies
				# FIXME --ignore-hold option fails with -y option unless the
				#       --allow-change-held-packages option is passed, which has
				#       the potential to break the system. How do we handle this?
				$use_release && \
				apt-get --ignore-hold -q0 -y -t $bin_release build-dep $bin_pkg=$bin_version 2>&1 | tee -a "$main_log_fname" || \
				apt-get --ignore-hold -q0 -y build-dep $bin_pkg=$bin_version 2>&1 | tee -a "$main_log_fname"

				# Redundant code should apt-get fail for some reason
				# between the call in get_apt_list and this one
				# eg: repo becomes unavailable
				[[ $PIPESTATUS[0] = "100" ]] && \
				{ echo "Failed to satisfy build dependencies for $src=$version/$release...not building" | tee -a "$build_fail_fname" "$main_log_fname" ; continue ; }
			fi
		else
			echo "Failed to satisfy build dependencies for $src=$version/$release...not building" | tee -a "$build_fail_fname" "$main_log_fname"
			continue

		fi

		# Some packages, such as x11proto-composite=1:0.4.2-2 may have a
		# debian/changelog.dch present. Rename it to debian/changelog to
		# prevent failing to update the changlogs
		[[ -e debian/changelog.dch ]] && \
		{ echo "Found a backup changelog for $src=$version/$release...renaming" | tee -a "$main_log_fname" ; mv debian/changelog.dch debian/changelog ; }

		# Update changelog
		su $user -c "debchange -p -D unstable -u low -l $suffix \"Local rebuild using $march_opt $mtune_opt\"" 2>&1
		[[ $? != "0" ]] && \
		{ echo "Failed to update changelog for $src=$version/$release...not building" | tee -a "$build_fail_fname" "$main_log_fname" ; continue ; }

		# Build package
		log_file="$log_dir/$src-$version.log"					# Build log filename
		echo -e "\nStarted build of $src=$version/$release on $(date)\n  Logfile is $log_file.gz" | tee -a "$main_log_fname"
		su $user -c "dpkg-buildpackage -i -F -us -uc" 2>&1 | tee "$log_file"

		if [[ ${PIPESTATUS[0]} = "0" ]]; then
			echo "Finished (success) on $(date)" | tee -a "$main_log_fname"
		else
			echo "Failed to build $src=$version/$release" | tee -a "$build_fail_fname"
			echo "Finished (failed) on $(date)" | tee -a "$main_log_fname"
		fi

		gzip -f "$log_file"										# Compress log file
		chown -f $user: "$log_file.gz"							# Change ownership of log file

		# On ZOL, memory usage goes up rapidly with the ARC.
		# It appears that ZOL isn't honouring the c_max var.
		# To prevent the possibility of OOMs we flush the
		# cache after every build. Disk access will increase
		# across the board until the cache re-populates, but
		# this is by far much better OOMs

		# Not sure about other fs. Comment out the next line
		# to check them

		# Do not do this if we are chrooted or in a container
		[[ -w /proc/sys/vm/drop_caches ]] && \
		sync && echo 3 > /proc/sys/vm/drop_caches

	done

	cd $old_PWD

}

move_files() {
	# Move files to the repository
	# We remove all files that may have been created by
	# failed-to-build sources

	local cmd_status
	local src

	shopt -s nullglob

	# Remove all files associated with failed-to-build packages
	if [[ -s "$build_fail_fname" ]]; then
		# Get list of possible packages that may have been
		# created by failed-to-build sources. We get the list
		# by looking at the packages given in the control file
		while read -r src; do
			src=${src%...*}
			src=${src##* }											# Get src=version/release
			echo -e "\n$src failed to build...removing files"
			src=${src%=*}											# Get name of source
			# Get list of packages built by this source package
			# BUG We do not intend for this script to build different versions
			#     of the same source at the same time. If this changes, then
			#     this will fail if one builds but the other fails to build
			tmp=$(grep '^[[:blank:]]*Package:' $build_dir/$src*/debian/control | cut -d' ' -f2)
			echo "  Removing all source files"
			tmp="$src-* $tmp"
			for file in $tmp; do
				echo "  Removing $build_dir/$file*"
				rm -rf "$build_dir/$file"*
			done
		done < "$build_fail_fname"
	fi

	# Move buildinfo files to buildinfo_dir
	tmp=
	cmd_status=true
	if [[ -d $buildinfo_dir ]]; then
		echo -e "\nMoving buildinfo files to $buildinfo_dir:"
		for file in $build_dir/*.buildinfo; do
			echo "  Moving $file to $buildinfo_dir/"
			mv -f -t "$buildinfo_dir" "$file" && \
			echo "   Success" || \
			{ echo "   Failed" ; cmd_status=false ; tmp="$tmp$file\n" ; }
		done

		$cmd_status || echo -e "\nFailed to move the following buildinfo files:\n$tmp"
	else
		echo -e "\n$buildinfo_dir does not exist, not moving buildinfo files"
	fi

	# Move newly built packages to the local repository
	tmp=
	cmd_status="0"
	if [[ -d $repo_dir ]]; then
		echo -e "\nMoving newly built packages to local repository:"
		for file in $build_dir/{*$suffix*.{deb,dsc,changes,debian.tar*,.diff*},*orig*}; do
			echo "  Moving $file to $repo_dir"
			mv -f -t "$repo_dir" "$file" && \
			echo "   Success" || \
			{ echo "   Failed" ; cmd_status="200" ; tmp="$tmp$file\n" ; }
		done
		[[ $cmd_status = "200" ]] && echo -e "\nFailed to move the following packages:\n$tmp"
	else
		cmd_status="100"												# repo_dir does not exist
	fi
	
	shopt -u nullglob

	return $cmd_status

}

cleanup() {
	# Leave the system in the pristine state it was in before we
	# started. This means that the list returned by:
	#   dpkg --get-selections
	# should be the same as the one we started off with after we
	# complete the clean-up process

	local c_install_list															# List of packages currently marked as 'install'
	local c_deinstall_list															# List of packages currently marked as 'deinstall'
	local i_list
	local c_list
	local i_count																	# Number of packages initially marked as 'install'
	local c_count																	# Number of packages currently marked as 'install'
	local count
	local i_release
	declare -A i_pkg																# List of packages marked for re-installation

	count_lines() {
		# Count number of lines passed in via $1
		let count=0
		while read -r line; do
			let count+=1
		done <<< "$1"
	}

	echo -e "\nCleaning up..."

	$keep_source_opt || { echo -e "\nRemoving source files" ; rm -rf $build_dir/* ; }

	# Remove build-dependencies that we installed during the build
	# process but, do not remove any that's in the install_list
	if [[ -s "$build_dep_fname" ]]; then
		tmp=
		i_list=$(cut -d':' -f1 <<< "$install_list")									# Remove arch component
		while read -r pkg; do
			grep -q "^$pkg$" <<< "$i_list" || tmp="$tmp$pkg "
		done <<< $(sort -u "$build_dep_fname")
		if [[ -n $tmp ]]; then
			echo -e "\nThe following build dependencies will be removed:\n\n$tmp"
			if apt-get -y remove $tmp 2>&1; then
				rm -f "$build_dep_fname"
			else
				echo -e "\nSome build dependencies were not removed"
			fi
		fi
	fi

	# Must be done in this order or else we purge the config files
	# of some packages we will re-install. Do not call create_lists
	# to recreate the list. The deinstall list must be re-created
	# after and only after we re-install any removed packages
	# TODO Try to install the same version as was previously installed.
	#      If the version was moved out of the repo, then look for it in the local archives.
	#      If it is not in the local archive, we have no choice but to install the version
	#      from the repo, which most likely is an upgrade

	echo -e "\nRe-install removed packages"
	tmp=
	c_install_list=$(dpkg --get-selections | grep -w install$ | cut -f1)			# Get list of currently installed packages
	if [[ $c_install_list != $install_list ]]; then
		# If a package from install_list is not in the
		# current install list, mark it for re-installation
		while read -r line; do
			grep -q "^${line%=*}$" <<< "$c_install_list" || i_pkg[${line#*/}]+="${line%=*} "
		done < "$install_list_fname"

		echo -e "The following packages were removed during the build process and will now be re-installed:\n"
		tmp=
		for rel in ${!i_pkg[@]}; do
			echo -e "From $rel:\n\n${i_pkg[$rel]}\n\n"
		done

		# If a required dependent package was not in the install_list, APT
		# will add this to the list. This can cause the final number of
		# packages marked as 'install' to be greater that the initial number

		# Install packages by release so that dependencies will be satisfied
		for rel in ${!i_pkg[@]}; do
			[[ $rel = "unknown" ]] && unset i_release || i_release="-t $rel"
			apt-get $i_release -y install ${i_pkg[$rel]} 2>&1
		done
	else
		echo "  No packages to re-install"
	fi

	echo -e "\nPurge removed packages"
	tmp=
	c_deinstall_list=$(dpkg --get-selections | grep -w deinstall$ | cut -f1)
	# If a package from deinstall_list is in the current
	# deinstall list, do not mark it for purging
	if [[ $c_deinstall_list != $deinstall_list ]]; then
		while read -r pkg; do
			grep -q "^$pkg$" <<< "$deinstall_list" || tmp="$tmp$pkg "
		done <<< "$c_deinstall_list"
		[[ -n $tmp ]] && \
		{ echo -e "\nThe configuration files of these packages will be removed:\n\n$tmp" ; apt-get -y purge $tmp 2>&1 ; }
	else
		echo "No packages to purge"
	fi

	# Check if we were successfull
	# We succeeded if our install_list and deinstall_list would exactly
	# match those produced by dpkg --get-selections at this point
	# However, we indicate a failure even if the number of installed
	# packages at this point is greater than what we started off with,
	# simply because our aim was to restore the system to the state it
	# was in when we started
	echo -e "\nChecking if we were successfull..."

	c_install_list=$(dpkg --get-selections | grep -w install$)

	# Count number of currently installed packages
	count_lines "$c_install_list"
	let c_count=$count

	# Count number of previously installed packages
	count_lines "$install_list"
	let i_count=$count

	if (( $i_count < $c_count )); then
		echo -e "  Failed\n    These additional packages were installed:"
		i_list="$installed_list"
		c_list="$c_install_list"
	elif (( $i_count > $c_count )); then
		echo -e "  Failed\n    These packages were not re-installed:"
		i_list="$c_install_list"
		c_list="$install_list"
	else
		echo "  Success"
		return
	fi

	while read -r pkg; do
		grep -q "^$pkg$" <<< "$i_list" || echo "      $pkg"
	done <<< "$c_list"

}

install_package() {
	# Install newly built packages
	# We get the list of packages to install/upgrade from
	# build_list but, we must first remove any failed-to-build
	# packages, and others, from the list
	
	# Remove packages excluded from building
	# eg: GCC and Linux kernel packages
	# See fetch_source function
	for pkg in $no_build_list; do
		build_list=${build_list/$pkg/}
	done

	# Get package names from build_list
	tmp=
	for pkg in $build_list; do
		pkg=${pkg%=*}
		tmp="$tmp$pkg "
	done

	# Remove failed-to-build packages
	if [[ -s $build_fail_fname ]]; then
		while read -r line; do
			if [[ -n $line ]]; then
				src=${line%=*}
				src=${src##* }								# Get name of source package
				pkg=${pkg_src_map_list%=$src *}				# Get binary package built by
				pkg=${pkg##* }								# this source package
				tmp=${tmp/$pkg }							# Remove package from list
			fi
		done < "$build_fail_fname"
	fi

	# No packages to install/upgrade
	[[ -z $tmp ]] && return 100

	echo -e "\nThe following newly built packages will be installed/upgraded:\n$tmp\n"
	get_confirmation || return

	# Allow user to review and make the final decision
	apt-get update 2>&1
	apt-get install $tmp 2>&1

}

check_helper_apps() {
	# Check that we have all required external programs and packages
	# installed that's needed for building Debian packages. Some packages
	# that we check for may be marked as 'essential' and should already
	# be installed.  We check for them just to be sure.
	# - apt package needed since we use the apt front-end to dpkg
	# - devscripts, fakeroot and build-essential packages needed for
	#   modifying and building the packages
	# - debtags needed for getting package tag information
	# - local-apt-repository package needed for local repository management
	# - build-essential package needed for building packages
	# - fakeroot package used for gain-root-command

	# Although some packages may be marked as essential and installed, apps may have been
	# deleted for some unknown reason. Check that it actually exist on $PATH

	local found
	local bail
	local packages
	local app
	local status
	
	found=true
	bail=false
	packages=(grep sed coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils coreutils login gzip procps)
	app=(grep sed date cut tail cp sort cat mkdir rm head tail tee true touch chown mkdir mkfifo false su gzip kill)

	# Check for external programs on $PATH. We do not use 'which' since this
	# is specific to the 'debianutils' package, which even though is marked as a required package,
	# it may or may not be installed or even broken, or the user may have screwed-up $PATH
	# In any case, we play it safe and do it the old fashion way
	for idx in "${!app[@]}"; do
		for path in ${PATH//:/ }; do
			if [[ -e "$path/${app[idx]}" ]]; then
				found=true
				break								# Found the app, check next one
			else
				found=false
			fi
		done
		$found || \
		{ bail=true ; echo "Cannot find ${app[idx]}. Please install/re-install the ${packages[idx]} package or check your PATH" ; }
	done

	$bail && return 100								# Return 100 to main() if we did not find any of the required apps

	# Check that packages required for building Debian packages are installed
	# dpkg -s returns the package staatus details:
	#	Package: ...
	#	Status: ...
	#	...
	# The 'Status:' line will be 'install ok installed' if the package
	# is installed and configured. We check for this status to determine
	# whether or not the package is properly installed and configured
	packages="apt build-essential debtags devscripts fakeroot local-apt-repository autopkgtest autodep8"
	for pkg in $packages; do
		tmp=
		tmp=$(dpkg -s $pkg 2>/dev/null)
		# Nothing is returned for an uninstalled package
		[[ -z $tmp ]] && { found=false ; echo "Please install the $pkg package" ; continue ; }
		while read -r line; do
			if [[ $line = Status:* ]]; then
				[[ $line != "Status: install ok installed" ]] && \
				{ found=false ; echo "Please install the $pkg package" ; }
				continue 2
			fi
		done <<< "$tmp"
	done

	$found || return 100							# Return 100 to main() if we did not find any of the required packages

}

create_lists() {
	# Populate our lists of package selection states

	packages_list=$(dpkg --get-selections)

	install_list=$(grep -w install$ <<< $packages_list | cut -f1)		# List of packages marked as 'install'
	hold_list=$(grep hold$ <<< $packages_list | cut -f1)				# List of packages marked as on 'hold'
	deinstall_list=$(grep deinstall$ <<< $packages_list | cut -f1)		# List of packages marked as 'deinstall'

	# Check for packages in an unknown/broken state
	broken_list=$(dpkg-query -f '${binary:Package} ${db:Status-Abbrev}\n' -W <<< $packages_list | grep R$ | cut -d' ' -f1)

	# Save our install and deinstall lists should we break
	# the system and need to restore it to it's former glory
	get_package_version "i" "$install_list"
	echo "$version_list" > "$install_list_fname"
	echo "$deinstall_list" > "$deinstall_list_fname"

}

create_pkg_depend_list() {
	# Create the list of dependent packages that we will also build
	# We do not use the --installed option when calling apt-cache with a
	# package that is not installed. This ensures we include all dependencies,
	# including those not already installed. See man(8) apt-cache
	# We replace build_list with the generated list since the generated
	# list also has the initial packages listed. The list of packages that
	# we will get the dependencies for are pass in via $@

	# NOTE This is a list of package dependencies,
	#      not to be confused with the list of build dependencies

	local installed_option								# --installed option for apt-cache
	local depend_list									# List of packages including dependencies
	local i_version										# Installed version of package
	local c_version										# Candidate version of package
	local count
	local num_pkg

	let count=1
	num_pkg="$#"
	for pkg in $@; do
		echo "($count/$num_pkg) Getting package dependencies for $pkg"
		c_version=${pkg#*=}								# Get candidate version
		c_version=${c_version%/*}
		pkg=${pkg%=*}									# Get package name
		i_version=$(apt-cache policy <<< $pkg | grep '[ ]*Installed:')
		[[ ${i_version##* } = $c_version ]] && installed_option="--installed" || installed_option=
		# Remove pkg from the list of dependencies. This will reduce the time
		# it takes when we call get_package_version below.
		tmp=$(apt-cache --no-pre-depends --no-suggests --no-conflicts --no-replaces --no-breaks --no-enhances \
						--no-recommends --recurse $installed_option depends "$pkg=$c_version" | grep -Ev "[[:blank:]]|^<.*>$|^$pkg$")
		depend_list="$depend_list$tmp "
		let count+=1
	done

	depend_list=$(tr ' ' '\n' <<< "$depend_list" | sort -u)	# Sort the list and remove duplicates

	get_package_version "c" "$depend_list"
	build_list=$(echo -e "$version_list\n$build_list")	# Re-add the list of removed packages

}

create_dirs_files() {
	# Create our directory structure and needed files
	# + $main_dir_
	#            |
	#            +--backup
	#            |
	#            +--build
	#            |
	#            +--buildinfo
	#            |
	#            +--log
	#            |
	#            +--tmp
	#            |
	#            |--build.depend
	#            |--build.fail

	local cmd_status
	local dir_list

	dir_list="$backup_dir $build_dir $buildinfo_dir $log_dir $tmp_dir"
	for d in $dir_list; do
		if [[ ! -d $d ]]; then
			mkdir -p "$d" 2>/dev/null || return 100					# Return 100 if we fail to create any of the dirs
		fi
	done

	[[ ! -d $repo_dir ]] && return 150								# Return 150 if /srv/local-apt-repository does not exist
	
	rm -f "$build_fail_fname" "$main_log_fname" "$tmp_dir"/pipe*

	touch "$build_dep_fname" 2>/dev/null || return 200				# Do not delete build.depend if it exists

	touch "$build_fail_fname" 2>/dev/null || return 210				# Create an empty build.fail file

	touch "$main_log_fname" 2>/dev/null || return 220				# Create an empty main.log file

	chown -R $user: "$main_dir"										# Change ownership to that of invoking user

}

sanitize_build_list() {
	# Sanitize the list of packages to build
	# We remove the following packages from the list:
	# - packages on hold
	# - virtual packages
	# - metapackages
	# - dummy packages
	# The list of packages to sanitize is passed in via $@

	local tags							# Package tags
	local c_version
	local apt_cache
	local count
	local num_pkg

	# Let debtag tell us what the tags are for meta and dummy packages
	# This prevents breakage if the tags change
	# There is no specific/reliable way to determine whether or not a package is virtual
	# For now we use apt-cache and grep the contents of the first line. eg:
	# $ apt-cache show cjet
	# N: Can't select versions from package 'cjet' as it is purely virtual
	# N: No packages found
	# or
	# $ apt-cache show libncurses-dev
	# N: Can't select versions from package 'libncurses-dev' as it is purely virtual
	# N: No packages found
	# This breaks if the line format changes
	
	# NOTE This fails if the packages are not tagged

	tags=$(debtags tagsearch metapackage dummy | cut -d'-' -f1)

	tmp=
	let count=0
	num_pkg="$#"
	for pkg in $@; do
		let count+=1
		echo "($count/$num_pkg) Checking $pkg"
		pkg=${pkg%/*}															# Remove release from pkg
		c_version=${pkg#*=}														# Candidate version of pkg
		pkg=${pkg%=*}															# Name of pkg

		apt_cache=$(apt-cache -q0 show $pkg=$c_version 2>&1)
		let l=${#count}+${#num_pkg}+3											# Num spaces is 3 greater than length of count+num_pkg
		set_spaces $l

		# Any virtual packages should have been removed from the list by
		# get_package_version but we check for virtual packages just in case
		read -r line <<< "$apt_cache"											# Read the first line of apt-cache
		[[ $line = "N: Can't select versions from package '$pkg' as it is purely virtual" ]] && \
		{ build_list=$(grep -v "^$pkg=$c_version" <<< "$build_list") ; tmp="$tmp$pkg=$c_version-(virtual) " ; echo "$spc   Found: $pkg=$c_version - virtual" ; continue ; }

		# Remove meta and dummy packages
		for tag in $tags; do
			[[ $apt_cache = *$tag* ]] && \
			{ build_list=$(grep -v "^$pkg=$c_version" <<< "$build_list") ; tmp="$tmp$pkg=$c_version-($tag) " ; echo "$spc   Found: $pkg=$c_version - $tag" ; continue 2 ; }
		done

		# Remove packages on hold
		[[ $hold_list = *$pkg* ]] && \
		{ build_list=$(grep -v "^$pkg=$c_version" <<< "$build_list") ; tmp="$tmp$pkg=$c_version-(hold) " ; echo "$spc   Found: $pkg=$c_version - hold" ; }

		# Remove already built packages. We can tell if the package was
		# already built if the candidate version contains the build suffix
		[[ $c_version = *$suffix* ]] && \
		{ build_list=$(grep -v "^$pkg=$c_version" <<< "$build_list") ; tmp="$tmp$pkg=$c_version-(already_built) " ; echo "$spc   Found: $pkg=$c_version - already built" ; }
	done

	if [[ -n $tmp ]]; then
		echo -e "\nThese packages will not be built:"
		for pkg in $tmp; do
			echo "  $pkg"
		done
	fi

}

check_data_sources() (
	# Check APT data sources that use the one-line-style format
	# Check that all APT data sources files have a corresponding
	# deb-src type entry for each deb type entry
	# APT data sources filenames must not contain a space character,
	# so we do not consider this in the code
	
	# Our purpose here is to add any missing deb-src entry, not to
	# check the validity of the line. Any malformed deb lines
	# missing a corresponding deb-src line will get a malformed deb-src
	# line added
	
	# NOTE If the deb-src entry points to a repo that does not provide sources,
	#	   apt-get update will emit a warning. This can be ignored since it does
	#	   not break the system. However, we will not be able to build source
	#	   packages from these repos

	# TODO Use associative array instead

	local files															# List of APT data sources files
	local fc
	local fc_src
	local deb_type														# Array of options, URI and sections for deb entry
	local deb_type_src													# Array of options, URI and sections for deb-src entry
	local found
	local idx
	local inc_idx
	local count
	
	# Array of missing deb-src entries and it's corresponding file
	# Format: deb_src[index] - newline seperated deb-src entries
	#		  deb_src[index+1] - APT data source filename
	local deb_src

	files="/etc/apt/sources.list /etc/apt/sources.list.d/*.list"
	fc=""
	fc_src=""
	deb_type=()
	deb_type_src=()
	found=false
	deb_src=()
	let idx=0

	shopt -s nullglob
	for file in $files; do
		inc_idx=false
		# Read contents of file skipping comment,blank and deb-src lines
		fc=$(grep '^deb ' $file | sort )
		mapfile -t deb_type <<< ${fc//deb /}							# Read deb lines into deb_type array
		
		# Read contents of file skipping comment,blank and deb lines
		fc_src=$(grep '^deb-src ' $file | sort )
		mapfile -t deb_type_src <<< ${fc_src//deb-src /}				# Read deb-src lines into deb_type_src array
		
		# Iterate over the elements in the deb_type array and compare them
		# against the deb-src entries in fc_src.
		# If we do not find a match we store the missing source entry against
		# it's data source file in deb_src
		for x in "${deb_type[@]}"; do
			found=true
			for y in "${deb_type_src[@]}"; do
				[[ "$x" = "$y" ]] && { found=true ; break; } || found=false
			done
			$found || \
			{ inc_idx=true ; deb_src[idx]=$(echo "${deb_src[idx]}\ndeb-src $x\n") ; deb_src[idx+1]="$file" ; }
		done
		$inc_idx && let idx+=2
	done

	# If we find one or more missing deb-src entry, inform the user and get
	# their permission to add them to the corresponding data source file
	if (( ${#deb_src[@]} > 0 )); then
		cat <<-EOF
			Missing one or more source line(s) in APT data sources.
			The following line(s) will be added to the named APT data source file:
			(Data sources are backed up to $backup_dir)
			
EOF

		for (( idx=0 ; idx<${#deb_src[@]}-1 ; idx+=2 )); do
			echo -e "These line(s) will be added to ${deb_src[idx+1]}:${deb_src[idx]}\n"
		done

		get_confirmation || return 1									# Get user's confirmation

		# Backup APT data sources
		for file in $files; do
			# No need to use basename since we do not expect the parameter
			# expansion to return an empty string
			cp --archive $file "$backup_dir/${file##*/}"
			[[ $? != "0" ]] && echo "Failed to backup $file"
		done

		# Write deb-src entries to corresponding APT data source files
		for (( idx=0 ; idx<${#deb_src[@]}-1 ; idx+=2 )); do
			echo -e "${deb_src[idx]}" >> "${deb_src[idx+1]}"
		done
	fi
	shopt -u nullglob

)

check_data_sources_deb822() (
	# Check APT data sources that use the DEB822-style format
	# See 'man(5) sources.list' if you don't know what this is all about
	# Check that all APT data sources files have a corresponding
	# deb-src type entry for each deb type entry
	# APT data sources filenames must not contain a space character,
	# so we do not consider this in the code

	# Our purpose here is to add any missing deb-src to the respective
	# stanza, not to check the validity of the stanza

	# We do not check for the ordering of the fieldnames
	# For example: If a stanza with 'Types: deb' has option1=value1
	# followed by option2=value2 and the corresponding 'Types: deb-src'
	# reverses this order, we may end up with a new 'Types: deb-src'
	# stanza for the corresponding 'Types: deb' stanza

	# We assume the fieldnames are listed in the order given in
	# man(5) sources.list
	
	# We let apt correlate and merge duplicate stanzas/fieldnames
	
	# NOTE The above comments was for a more robust and complicated checker.
	#      I've left it in place should I decide to re-visit it.

	# For now we simply set the value of the Types fieldname in each stanza
	# containing only a 'deb' entry to 'deb deb-src'
	
	# NOTE If the deb-src entry points to a repo that does not provide sources,
	#	   apt-get update will emit a warning. This can be ignored since it does
	#	   not break the system. However, we will not be able to build source
	#	   packages from these repos

	local files											# DEB822-style APT data sources are in
														# /etc/apt/sources.list.d/*.sources
	local regex											# Regex to search for

	files="/etc/apt/sources.list.d/*.sources"
	regex="^Types:[ ]+deb[ ]*$"

	# Backup APT data sources
	shopt -s nullglob
	for file in $files; do
		# No need to use basename since we do not expect the parameter
		# expansion to return an empty string
		cp --archive $file "$backup_dir/${file##*/}"
		[[ $? != "0" ]] && echo "Failed to backup $file"
	done

	# Check for APT data sources that we will modify
	tmp=
	for file in $files; do
		grep -qE "$regex" "$file" && \
		tmp="$tmp\n$file"
	done
	
	# Inform user if we are modifying files
	if [[ -n $tmp ]]; then
		echo -e "The following APT data source(s) will be modified:$tmp\n(Data sources are backed up to $backup_dir)"
		get_confirmation || return 1
		sed -r -i "s,$regex,Types: deb deb-src,g" $files
	fi
	shopt -u nullglob

)

main() {
	# We do some sanity checks to verify the integrity of the system before processing any
	# of the commands. We do not build if there are broken package(s). We also check that
	# all of the repo list files have deb-src line)s) in them

	# Get invoking username
	while read -r line; do
		if  [[ $line = *$HOME* ]]; then
			user=${line%%:*}
			[[ $user = "root" ]] && \
			show_help "Must pass preserve-environment option to gain-root-command. See 'Usage' below"
			break
		fi
	done < "$passwd_file"

	# Do not run these functions if we are trying to repair the system
	if [[ $1 != "repair" ]]; then
		# Check that we have the necessary external apps and packages installed
		check_helper_apps || exit 1

		# Create directory structure
		create_dirs_files
		case $? in
			100)
				bail_out "Failed to create directory structure...bailing"
			;;
			150)
				bail_out "Unable to locate $repo_dir...bailing"
			;;
			200)
				bail_out "Failed to create $build_dep_fname...bailing"
			;;
			210)
				bail_out "Failed to create $build_fail_fname...bailing"
			;;
			220)
				bail_out "Failed to create $main_log_fname...bailing"
		esac

		# Start the main logfile
		start_logfile "$main_log_fname"

		# Make sure we can download sources
		check_data_sources || exit 1

		check_data_sources_deb822 || exit 1

		# Resynchronize the package index files
		echo "Resynchronizing the package index files"
		apt-get update 2>&1

		# Create our lists of package selection states
		create_lists
		[[ -n $broken_list ]] && \
		bail_out "Fix these package(s) that are in an unknown/broken state:\n$broken_list"
	fi

	# Process the parsed command and any arguments
	case $1 in
		install)
			shift
			build_list="$@"
			# Check that the list of packages is valid
			for pkg in $build_list; do
				[[ $(apt-cache pkgnames $pkg | grep ^$pkg$) != $pkg ]] && \
				bail_out "$pkg is not a valid package name...bailing"
			done
		;;
		upgrade)
			# Get list of upgradeable packages
			# Let APT do the heavy lifting here
			get_apt_list "upgrade" || \
			bail_out "Could not get list of upgradeable packages...bailing"
			[[ -z $apt_list ]] && \
			bail_out "No packages to upgrade...bailing"
			build_list="$apt_list"
		;;
		world)
			depend_opt=false							# No need to pull in dependencies for world
			build_list="$install_list"
		;;
		repair)
			# Try to repair the system if a crashed occurred
			# before the last invocation of the script completed
			# Any options passed with this command are ignored
			[[ ! -s $install_list_fname ]] && \
			{ echo "'$install_list_fname' does not exists or it is empty...bailing" ; exit 1 ; }
			# Get list of packages previously marked as 'install' and 'deinstall'
			install_list=$(cut -d"=" -f1 "$install_list_fname")
			[[ -s $deinstall_list_fname ]] && deinstall_list=$(<"$deinstall_list_fname")
			keep_source_opt=true						# Do not remove any source files
			start_logfile "$repair_log_fname"			# Start the main logfile
			cleanup
			exit
		;;
	esac

	get_package_version "c" "$build_list"
	build_list="$version_list"

	# Get list of dependent packages
	$depend_opt && create_pkg_depend_list $build_list

	# Sanitize the list of packages to build
	sanitize_build_list $build_list
	[[ -z $build_list ]] && bail_out "No packages to build...bailing"

	# Fetch and unpack source packages
	fetch_source
	if [[ -n $no_source_list ]]; then
		echo -e "\nUnable to find sources for the following packages (not building):"
		for pkg in $no_source_list; do
			echo "  $pkg"
		done
	fi

	if [[ -n $fail_dl_list ]]; then
		echo -e "Failed to download the following source packages:"
		for src in $fail_dl_list; do
			echo "  $src"
		done
		bail_out "Please try again to download the failed sources...bailing"
	fi

	[[ -z $source_list ]] && bail_out "No sources to build...bailing"

	# Stop the main logfile
	stop_logfile
	
	# Start the build process
	# TODO Try -J1 or -j1 depending on dpkg version for
	#      failed builds. If that fails also, are we chrooted?
	
	# TODO Some packages such as glib2.0 will still fail the re-build
	#      unless the source is re-downloaded. How best can we handle
	#      such situations generically for all packages that fail to
	#      build. Probably, a seperate rebuild_package function?

	build_package								# Do all redirection from within the function
	
	start_logfile "$main_log_fname"				# Restart the main logfile

	if [[ -s "$build_fail_fname" ]]; then
		echo -e "\nThe following source(s) failed to build:"
		while read -r line; do
			echo "  $line"
		done < "$build_fail_fname"
	else
		echo -e "\nAll source(s) were successfully built"
	fi

	# Move files/packages to their final destinations
	move_files
	case $? in
		100)
			bail_out "$repo_dir does not exist...bailing"
		;;
		200)
			echo -e "\nMove the above packages manually before selecting 'y|Y'"
			echo -e "They will be deleted if you do not move them!\n"
			get_confirmation || \
			bail_out "Failed to move some package(s)...bailing"
		;;
	esac

	# Leave the system in a prestine state
	cleanup

	# Install our newly built packages
	install_package || echo -e "No packages to install/upgrade"

	exit

}

# Check that we are runnng as root
[[ $UID != "0" ]] && show_help "Must be run with root privileges. See 'Usage' below"

# Parse options and commands
cmds="install upgrade world retry repair"
march=false
while : ; do
	do_shift=false
	opt_arg=
	msg=
	case $1 in
		--*)												# Long option of the form 'opt[=arg]'
			opt=${1#--}
			[[ $opt = *=* ]] && \
			{ opt=${opt%=*} ; opt_arg=${1#*=} ; }			# Long option of the form 'opt=arg'
		;;
		-?)													# Short option of the form '-o [arg]'
			opt=${1#-}										# Extract short option
			# If $2 does not start with a'-' or is not one
			# of the commands, then it's a possible argument
			if [[ ${2:0:1} != "-" ]] && \
			   [[ $2 != "install" && $2 != "upgrade" && $2 != "world" && $2 != "retry" && $2 != "repair" ]]; then
			   { opt_arg=$2 ; do_shift=true ; }
			fi
		;;
		-*)													# Short option of the form '-oarg'
			opt=${1:1:1}									# Extract short option
			opt_arg=${1:2}									# Extract argument
		;;
		install|upgrade|world|repair)						# Command
			if [[ $1 == "install" && -z $2 ]]; then
				show_help "Command 'install' needs at least one package to build and install"
			else
				main $@
			fi
		;;
		*)
			if [[ -z $1 ]]; then
				show_help "Must give a command"
			else
				show_help "Unknown command '$1'"
			fi
	esac

	# Options must never be the last parameter passed
	# except for -h or --help
	if [[ $opt != 'h' && $opt != "help" ]]; then
		if [[ -z $2 ]]; then
			(( ${#opt} == 1 )) && opt="-$opt" || opt="--$opt"
			show_help "$opt cannot be last parameter"
		fi
	fi

	# Options that require an argument must always get one
	# Checking this here reduces code duplication below where
	# we process and set our options
	case $opt in
		a|march)
			msg="-a|--march requires a CPU type"
 		;;
 		t|mtune)
			msg="-t|--mtune requires a CPU type"
		;;
 		o|optimize-level)
 			msg="-o|--optimize-level requires either of 1|2|3"
 		;;
 		n|name)
 			msg="-n|--name requires the user's full name"
 		;;
 		e|email)
 			msg="-e|--email requires an e-mail address"
 		;;
 		r|target-release)
			msg="-t|--target-release requires a release"
		;;
	esac

	[[ -z $opt_arg && -n $msg ]] && show_help "$msg"
	for c in $cmds; do
		[[ $opt_arg = $c ]] && show_help "$msg"
	done

	# Set options
	case $opt in
		h|help)
			show_help
		;;
		V|version)
			echo "$app_name v$version"
			exit 0
		;;
		s|silent)
			silent_opt=true
		;;
		d|dependencies)
			depend_opt=true
		;;
		k|keep-source)
			keep_source_opt=true
		;;
		b|build-dbgsym)
			dbgsym_opt=true
		;;
		c|run-checks)
			checks_opt=true
		;;
		v|verbose)
			verbose_opt=true
		;;
		a|march)
			march_opt="-march=$opt_arg"
			mtune_opt="-mtune=$opt_arg"
			march=true
			tmp="${march_opt#*=}"				# Set our local build suffix to CPU type
			suffix="+${tmp//-/}"				# after removing all '-'
		;;
		t|mtune)
			$march || show_help "-t|--mtune must be given after --march option"
			mtune_opt="-mtune=$opt_arg"
		;;
		o|optimize-level)
			if (( $opt_arg < 1 )) || (( $opt_arg > 3 )); then
				show_help "-o|--optimize-level requires either of 1|2|3"
			fi
			optimize_opt="-O$opt_arg"
		;;
		n|name)
			deb_name="$opt_arg"
		;;
		e|email)
			deb_email="$opt_arg"
		;;
		r|target-release)
			release_opt="$opt_arg"
		;;
		*)
			(( ${#opt} == 1 )) && opt="-$opt" || opt="--$opt"
			show_help "Unknown option '$opt'"
	esac
	$do_shift && shift
	shift
done
