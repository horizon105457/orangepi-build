#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot
# The sd card's root path is accessible via $SDCARD variable.

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4
OVERLAY_ARG=$5
ARCH=$6

# Return code used by overlay validation to indicate a clean skip (mode=none).
OVERLAY_VALIDATE_SKIP=3

# =========================
# Generic utility helpers
# =========================

SetOwnerModeIfFileExists() {
	local path="$1"
	local owner="$2"
	local mode="$3"
	local label="$4"

	if [[ -f "${path}" ]]; then
		chown "${owner}" "${path}"
		chmod "${mode}" "${path}"
		echo "Fixed ${label} ownership and mode"
	fi
}

AptUpdate() {
	apt-get update
}

AptInstall() {
	apt-get install -y "$@"
}

AptInstallBestEffort() {
	apt-get install -y "$@" 2>/dev/null || true
}

AptFixBrokenInstall() {
	apt-get -f install -y
}

DownloadFile() {
	local url="$1"
	local output_path="$2"

	if command -v curl >/dev/null 2>&1; then
		curl -fL -o "${output_path}" "${url}"
		return $?
	fi

	if command -v wget >/dev/null 2>&1; then
		wget -O "${output_path}" "${url}"
		return $?
	fi

	echo "[download:ERROR] Neither curl nor wget is available" >&2
	return 1
}

EnsureCustomizeImageContext() {
	local expected_path="/tmp/customize-image.sh"
	local actual_path

	actual_path="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
	if [[ "${actual_path}" != "${expected_path}" ]]; then
		echo "[main:FATAL] customize-image.sh must run from ${expected_path} inside the image chroot" >&2
		echo "[main:FATAL] Current path: ${actual_path}" >&2
		return 1
	fi

	if [[ ! -d /tmp/overlay && "${OVERLAY_ARG:-none}" != "none" ]]; then
		echo "[main:FATAL] Missing /tmp/overlay bind mount inside image chroot" >&2
		return 1
	fi

	return 0
}

# =========================
# Overlay merge helpers
# =========================

OverlayResolveWhitelist() {
	local -n whitelist_ref="$1"
	local whitelist_default=(
		"etc/NetworkManager/system-connections"
		"etc/default"
		"etc/ssh"
		"etc/hostname"
		"etc/hosts"
		"root/.ssh"
		"usr/local/bin"
		"usr/local/sbin"
		"usr/local/share"
		"etc/systemd/system"
		"etc/sysctl.d"
		"etc/security/limits.d"
		"etc/udev/rules.d"
		"etc/systemd/system.conf.d"
		"opt"
	)

	whitelist_ref=()
	if [[ -n "${OVERLAY_WHITELIST:-}" ]]; then
		read -r -a whitelist_ref <<< "${OVERLAY_WHITELIST}"
		echo "[overlay] Whitelist source: OVERLAY_WHITELIST environment"
	else
		whitelist_ref=("${whitelist_default[@]}")
		echo "[overlay] Whitelist source: built-in default"
	fi
}

OverlayValidateInputs() {
	local overlay_dir="$1"
	local mode="$2"
	local exit_on_error="$3"
	local file_count

	echo "[overlay] ========== Beginning Overlay Merge =========="
	echo "[overlay] Mode: $mode"
	echo "[overlay] Overlay directory: $overlay_dir"

	if [[ ! -d "${overlay_dir}" ]]; then
		echo "[overlay:ERROR] Overlay directory not found: ${overlay_dir}" >&2
		if [[ $exit_on_error -eq 1 ]]; then
			echo "[overlay:FATAL] Cannot proceed without overlay directory. Exiting." >&2
			return 1
		fi
		return 0
	fi

	if [[ "$mode" == "none" ]]; then
		echo "[overlay] Mode is 'none' - skipping overlay merge"
		return ${OVERLAY_VALIDATE_SKIP}
	fi

	if [[ "$mode" != "partial" && "$mode" != "full" ]]; then
		echo "[overlay:ERROR] Invalid OVERLAY_MERGE mode: '$mode' (allowed: none|partial|full)" >&2
		echo "[overlay:FATAL] Invalid mode. Exiting." >&2
		return 1
	fi

	file_count=$(find "${overlay_dir}" -type f 2>/dev/null | wc -l)
	if [[ $file_count -eq 0 ]]; then
		echo "[overlay:WARN] Overlay directory is empty (no files found)" >&2
		if [[ $exit_on_error -eq 1 ]]; then
			echo "[overlay:WARN] Proceeding anyway (overlay might be built on-the-fly)" >&2
		fi
	else
		echo "[overlay] Found $file_count files in overlay directory"
	fi

	if ! command -v rsync >/dev/null 2>&1; then
		echo "[overlay:ERROR] rsync not found - cannot merge overlay" >&2
		echo "[overlay:FATAL] rsync is required. Exiting." >&2
		return 1
	fi
	echo "[overlay] rsync available: $(which rsync)"

	return 0
}

OverlayPrepareRsyncOptions() {
	local -n rsync_opts_ref="$1"
	local -n backup_dir_ref="$2"
	local ts
	local backup_enabled="${OVERLAY_BACKUP:-1}"

	rsync_opts_ref=()
	backup_dir_ref=""
	ts=$(date +%Y%m%d-%H%M%S)

	if [[ "${backup_enabled}" == "1" ]]; then
		backup_dir_ref="/root/overlay-backups/${ts}"
		if ! mkdir -p "${backup_dir_ref}" 2>/dev/null; then
			echo "[overlay:ERROR] Failed to create backup directory: ${backup_dir_ref}" >&2
			echo "[overlay:FATAL] Cannot create backup directory. Exiting." >&2
			return 1
		fi
		rsync_opts_ref+=(--backup --backup-dir="${backup_dir_ref}")
		echo "[overlay] Backup enabled: $backup_dir_ref"
	else
		echo "[overlay] Backup disabled (OVERLAY_BACKUP=0)"
	fi

	if [[ "${OVERLAY_DRYRUN:-0}" == "1" ]]; then
		rsync_opts_ref+=(--dry-run --itemize-changes)
		echo "[overlay] DRY-RUN mode enabled - no changes will be made"
	fi

	rsync_opts_ref+=(-aHAX --numeric-ids)

	return 0
}

OverlayMergeFull() {
	local overlay_dir="$1"
	local -n rsync_opts_ref="$2"
	local -n excludes_ref="$3"

	echo "[overlay] Mode: FULL - syncing entire overlay directory"
	if ! rsync "${rsync_opts_ref[@]}" "${excludes_ref[@]}" "${overlay_dir}/" / 2>&1 | tee -a /var/log/overlay-merge.log; then
		echo "[overlay:ERROR] rsync failed during full merge" >&2
		return 1
	fi

	return 0
}

OverlayMergePartial() {
	local overlay_dir="$1"
	local -n rsync_opts_ref="$2"
	local -n whitelist_ref="$3"
	local merged_count=0
	local skipped_count=0
	local merge_status=0
	local rel src dst

	echo "[overlay] Mode: PARTIAL - syncing whitelisted directories only"
	echo "[overlay] Whitelist: ${whitelist_ref[*]}"

	for rel in "${whitelist_ref[@]}"; do
		src="${overlay_dir}/${rel}"
		dst="/${rel}"

		if [[ ! -e "${src}" ]]; then
			echo "[overlay] SKIP: ${rel} (not in overlay)"
			((skipped_count++))
			continue
		fi

		echo "[overlay] Merging: ${rel}"
		mkdir -p "$(dirname "${dst}")" || {
			echo "[overlay:ERROR] Failed to create directory: $(dirname "${dst}")" >&2
			merge_status=1
			continue
		}

		if [[ -d "${src}" ]]; then
			if ! rsync "${rsync_opts_ref[@]}" "${src}/" "${dst}/" 2>&1 | tee -a /var/log/overlay-merge.log; then
				echo "[overlay:ERROR] rsync failed for directory: ${rel}" >&2
				merge_status=1
				continue
			fi
		else
			if ! rsync "${rsync_opts_ref[@]}" "${src}" "${dst}" 2>&1 | tee -a /var/log/overlay-merge.log; then
				echo "[overlay:ERROR] rsync failed for file: ${rel}" >&2
				merge_status=1
				continue
			fi
		fi
		((merged_count++))
	done

	echo "[overlay] Partial merge complete: $merged_count merged, $skipped_count skipped"
	return $merge_status
}

OverlayPostMergePermissionsFix() {
	local f home user uid gid

	if [[ "${OVERLAY_DRYRUN:-0}" == "1" ]]; then
		return 0
	fi

	echo "[overlay] ========== Post-Merge Permissions Fix =========="

	if [[ -d /etc/NetworkManager/system-connections ]]; then
		echo "[overlay] Setting NetworkManager connection permissions"
		if ! chmod 600 /etc/NetworkManager/system-connections/* 2>/dev/null; then
			echo "[overlay:WARN] Failed to chmod NetworkManager connections" >&2
		fi
		if ! chown root:root /etc/NetworkManager/system-connections/* 2>/dev/null; then
			echo "[overlay:WARN] Failed to chown NetworkManager connections" >&2
		fi
	fi

	echo "[overlay] Setting SSH key permissions"
	for f in /etc/ssh/*key /root/.ssh/id_* /root/.ssh/*_key; do
		[[ -e "$f" ]] || continue
		if ! chmod 600 "$f" 2>/dev/null; then
			echo "[overlay:WARN] Failed to chmod: $f" >&2
		fi
		if ! chown root:root "$f" 2>/dev/null; then
			echo "[overlay:WARN] Failed to chown: $f" >&2
		fi
	done

	if [[ -d /home ]]; then
		echo "[overlay] Setting user home directory permissions"
		for home in /home/*; do
			[[ -d "$home" ]] || continue
			user="$(basename "$home")"
			if ! getent passwd "$user" >/dev/null 2>&1; then
				continue
			fi
			uid="$(getent passwd "$user" | cut -d: -f3)"
			gid="$(getent passwd "$user" | cut -d: -f4)"
			if [[ -d "$home/.ssh" ]]; then
				chown -R "${uid}:${gid}" "$home/.ssh" 2>/dev/null || true
				chmod 700 "$home/.ssh" 2>/dev/null || true
				find "$home/.ssh" -maxdepth 1 -type f \( -name 'id_*' -o -name '*_key' -o -name 'authorized_keys' \) ! -name '*.pub' -exec chmod 600 {} + 2>/dev/null || true
				find "$home/.ssh" -maxdepth 1 -type f -name '*.pub' -exec chmod 644 {} + 2>/dev/null || true
			fi
		done
	fi
}

# Unified overlay merge (none/partial/full) with comprehensive error handling
MergeOverlayToRoot() {
	local overlay_dir="/tmp/overlay"
	local mode="${OVERLAY_ARG:-none}"
	local exit_on_error=1  # Default: exit on failure
	local whitelist=()
	local excludes=(
		--exclude=/proc
		--exclude=/sys
		--exclude=/dev
		--exclude=/run
		--exclude=/tmp
		--exclude=/mnt
		--exclude=/media
		--exclude=/boot
		--exclude=/etc/fstab
		--exclude=/etc/mtab
	)
	local rsync_opts=()
	local backup_dir=""
	local merge_status=0
	local validation_status

	OverlayResolveWhitelist whitelist

	OverlayValidateInputs "${overlay_dir}" "${mode}" "${exit_on_error}"
	validation_status=$?
	if [[ ${validation_status} -eq ${OVERLAY_VALIDATE_SKIP} ]]; then
		return 0
	elif [[ ${validation_status} -ne 0 ]]; then
		return ${validation_status}
	fi

	if ! OverlayPrepareRsyncOptions rsync_opts backup_dir; then
		return 1
	fi

	echo "[overlay] ========== Merging Files =========="
	echo "[overlay] rsync options: ${rsync_opts[*]}"

	if [[ "${mode}" == "full" ]]; then
		if ! OverlayMergeFull "${overlay_dir}" rsync_opts excludes; then
			merge_status=1
		fi
	else
		if ! OverlayMergePartial "${overlay_dir}" rsync_opts whitelist; then
			merge_status=1
		fi
	fi

	if [[ $merge_status -ne 0 ]]; then
		echo "[overlay:ERROR] Merge operation failed" >&2
		if [[ $exit_on_error -eq 1 ]]; then
			echo "[overlay:FATAL] Merge failed. Exiting." >&2
			return 1
		fi
	fi

	OverlayPostMergePermissionsFix

	echo "[overlay] ========== Overlay Merge Complete =========="
	echo "[overlay] Mode: $mode, Status: $([ $merge_status -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')"
	if [[ -n "$backup_dir" ]]; then
		echo "[overlay] Backup directory: $backup_dir"
	fi
	echo "[overlay] Log file: /var/log/overlay-merge.log"

	return $merge_status
}

# =========================
# Feature installers
# =========================

InstallMDNS() {
	# Enable mDNS (Avahi) support for zero-config networking
	if ! command -v avahi-daemon &>/dev/null; then
		echo "Installing mDNS support (avahi-daemon)..."
		apt-get install -y avahi-daemon libnss-mdns avahi-utils
		systemctl enable avahi-daemon
		systemctl start avahi-daemon
		echo "mDNS support installed and enabled"
	fi
} # InstallMDNS

InstallROS2() {
	# Unified ROS2 installer — single function for all supported distros.
	# Usage: InstallROS2 <distro>
	#   distro: "humble" (Ubuntu 22.04) | "jazzy" (Ubuntu 24.04)
	#
	# The function handles repo bootstrap, base packages, dev toolchain,
	# alternative RMW backends, rosdep init, and shell environment setup.
	# Robot development extras are installed on a best-effort basis.
	local distro="$1"

	if [[ -z "${distro}" ]]; then
		echo "[ros2:ERROR] No distro specified. Usage: InstallROS2 humble|jazzy" >&2
		return 1
	fi

	echo "Installing ROS2 ${distro^} (base + development dependencies)..."
	local ros_apt_source_version
	local ros_apt_source_deb="/tmp/ros2-apt-source.deb"
	local ubuntu_codename_resolved

	export DEBIAN_FRONTEND=noninteractive

	# Base tools required by repository bootstrap and development workflow
	AptUpdate
	AptInstall \
		curl \
		wget \
		ca-certificates \
		software-properties-common \
		build-essential \
		cmake \
		git \
		pkg-config \
		python3-pip \
		python3-venv \
		python3-dev

	# Enable universe repository (required by several ROS-related dependencies)
	add-apt-repository universe -y || true

	# Detect Ubuntu codename
	. /etc/os-release
	ubuntu_codename_resolved="${UBUNTU_CODENAME:-${VERSION_CODENAME}}"
	if [[ -z "${ubuntu_codename_resolved}" ]]; then
		echo "[ros2:ERROR] Failed to detect Ubuntu codename from /etc/os-release" >&2
		return 1
	fi

	# Resolve latest ros-apt-source release version
	ros_apt_source_version="$(curl -fsSL https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}')"
	if [[ -z "${ros_apt_source_version}" ]]; then
		echo "[ros2:ERROR] Failed to resolve ros-apt-source release version" >&2
		return 1
	fi

	# Download and install ros-apt-source for this codename
	local ros_apt_source_url="https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ros_apt_source_version}/ros2-apt-source_${ros_apt_source_version}.${ubuntu_codename_resolved}_all.deb"
	if ! DownloadFile "${ros_apt_source_url}" "${ros_apt_source_deb}"; then
		echo "[ros2:ERROR] Failed to download ros2-apt-source package" >&2
		return 1
	fi
	if ! dpkg-deb --info "${ros_apt_source_deb}" >/dev/null 2>&1; then
		echo "[ros2:ERROR] Downloaded ros2-apt-source package is invalid: ${ros_apt_source_deb}" >&2
		return 1
	fi
	dpkg -i "${ros_apt_source_deb}"

	# Install ROS2 base and developer essentials (C++/Python/colcon/rosdep)
	AptUpdate
	AptInstall \
		"ros-${distro}-ros-base" \
		ros-dev-tools \
		python3-colcon-common-extensions \
		python3-rosdep \
		python3-vcstool \
		python3-argcomplete \
		python3-rosinstall-generator

	# Install commonly used alternative RMW implementations so runtime transport
	# selection does not require rebuilding the image.
	AptInstallBestEffort \
		"ros-${distro}-rmw-cyclonedds-cpp" \
		"ros-${distro}-rmw-zenoh-cpp"

	# ==============
	# Recommended robot development extras (best-effort, non-blocking)
	# ==============
	#
	# These packages are valuable for typical control/perception/planning
	# workflows but not strictly required. Installation failures are silently
	# tolerated so the image build does not break on transient repo issues.
	local ros_extras=()
	ros_extras+=("ros-${distro}-tf2-tools")               # view_frames, tf2_echo
	ros_extras+=("ros-${distro}-xacro")                    # URDF preprocessing
	ros_extras+=("ros-${distro}-robot-state-publisher")    # publish TF from joint states
	ros_extras+=("ros-${distro}-joint-state-publisher")    # joint state GUI
	ros_extras+=("ros-${distro}-teleop-twist-keyboard")    # keyboard teleop
	ros_extras+=("ros-${distro}-teleop-twist-joy")         # joystick teleop
	ros_extras+=("ros-${distro}-image-transport-plugins")  # compressed/decompressed image
	ros_extras+=("ros-${distro}-compressed-image-transport")
	ros_extras+=("ros-${distro}-robot-localization")       # IMU+GPS+odom sensor fusion
	ros_extras+=("ros-${distro}-ros2-control")             # robot hardware abstraction
	ros_extras+=("ros-${distro}-ros2-controllers")         # PID / joint trajectory ctrl
	ros_extras+=("ros-${distro}-cv-bridge")                # ROS-OpenCV bridge

	if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
		ros_extras+=("ros-${distro}-rviz2")                # 3D visualization
		ros_extras+=("ros-${distro}-rqt-image-view")       # image viewer plugin
	fi

	AptInstallBestEffort "${ros_extras[@]}"

	# Initialize rosdep database in non-interactive way
	if command -v rosdep >/dev/null 2>&1; then
		if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
			rosdep init || true
		fi
		rosdep update || true
	fi

	# Setup ROS2 environment for all users/shells
	cat > "/etc/profile.d/ros2-${distro}.sh" <<-ROSENV
	#!/bin/sh
	if [ -f "/opt/ros/${distro}/setup.sh" ]; then
		. "/opt/ros/${distro}/setup.sh"
	fi
	ROSENV
	chmod 0644 "/etc/profile.d/ros2-${distro}.sh"

	local bash_rc_line="source /opt/ros/${distro}/setup.bash"
	grep -qxF "${bash_rc_line}" /etc/bash.bashrc || echo "${bash_rc_line}" >> /etc/bash.bashrc
	grep -qxF "${bash_rc_line}" /etc/skel/.bashrc || echo "${bash_rc_line}" >> /etc/skel/.bashrc
	if [[ -f /etc/zsh/zshrc ]]; then
		grep -qxF "${bash_rc_line}" /etc/zsh/zshrc || echo "${bash_rc_line}" >> /etc/zsh/zshrc
	fi

	echo "ROS2 ${distro^} (base + dev deps + recommended extras) installed successfully"
} # InstallROS2

InstallOpenCV() {
	# Install OpenCV for computer vision tasks
	echo "Installing OpenCV..."

	# Install OpenCV with Python bindings and development libraries
	apt-get install -y \
		python3-opencv \
		libopencv-dev \
		opencv-data \
		libopencv-contrib-dev 2>/dev/null || true

	# Install ROS2 cv_bridge (distro-agnostic: detect installed ROS2)
	if [ -d /opt/ros/jazzy ]; then
		apt-get install -y ros-jazzy-cv-bridge 2>/dev/null || true
	elif [ -d /opt/ros/humble ]; then
		apt-get install -y ros-humble-cv-bridge 2>/dev/null || true
	fi

	echo "OpenCV installed successfully"
} # InstallOpenCV

InstallDroneCAN() {
	# Install user-space DroneCAN tooling for CAN device bring-up and diagnostics.
	echo "Installing DroneCAN Python package..."

	if ! command -v pip3 >/dev/null 2>&1; then
		AptUpdate
		AptInstall python3-pip
	fi

	InstallPipUser dronecan || echo "[dronecan:WARN] dronecan install failed (optional)"
	echo "DroneCAN Python package installed successfully"
} # InstallDroneCAN

EnsureRenderGroupAccess() {
	# New RK3588 NPU path uses DRM render nodes (/dev/dri/renderD*).
	# Keep secure defaults (0660, root:render) and grant access by group membership.
	if ! getent group render >/dev/null 2>&1; then
		groupadd -f render || true
	fi

	local home user
	for home in /home/*; do
		[[ -d "${home}" ]] || continue
		user="$(basename "${home}")"
		getent passwd "${user}" >/dev/null 2>&1 || continue
		if id -nG "${user}" 2>/dev/null | tr ' ' '\n' | grep -qx "render"; then
			echo "[accel] User ${user} already in render group"
			continue
		fi
		if usermod -aG render "${user}"; then
			echo "[accel] Added user ${user} to render group"
		else
			echo "[accel:WARN] Failed to add user ${user} to render group" >&2
		fi
	done
} # EnsureRenderGroupAccess

InstallAccelHealthcheck() {
	local healthcheck_script="/usr/local/sbin/opibot-accel-healthcheck"
	local healthcheck_service="/etc/systemd/system/opibot-accel-healthcheck.service"

	# Static payloads should come from overlay so they stay reviewable and can be
	# consumed by image builds without duplicating content in this script.
	if [[ ! -x "${healthcheck_script}" ]]; then
		echo "[accel:ERROR] Missing executable healthcheck script: ${healthcheck_script}" >&2
		return 1
	fi

	if [[ ! -f "${healthcheck_service}" ]]; then
		echo "[accel:ERROR] Missing healthcheck unit: ${healthcheck_service}" >&2
		return 1
	fi

	systemctl daemon-reload || true
	systemctl enable opibot-accel-healthcheck.service || true
	echo "[accel] Installed opibot-accel-healthcheck service"
} # InstallAccelHealthcheck

InstallOptionalNoMachine() {
	# Optional NoMachine install.
	# Priority:
	# 1) /tmp/overlay/packages/nomachine/*.deb
	# 2) NOMACHINE_DEB_URL environment variable
	# Non-blocking by default; set NOMACHINE_REQUIRED=1 to fail build on error.
	local nm_overlay_dir="/tmp/overlay/packages/nomachine"
	local nm_url="${NOMACHINE_DEB_URL:-}"
	local nm_required="${NOMACHINE_REQUIRED:-0}"
	local nm_deb=""

	if dpkg-query -W -f='${Status}' nomachine 2>/dev/null | grep -q "install ok installed"; then
		echo "[nomachine] Already installed, skipping"
		return 0
	fi

	if [[ -d "${nm_overlay_dir}" ]]; then
		nm_deb="$(find "${nm_overlay_dir}" -maxdepth 1 -type f -name '*.deb' | sort | head -n1)"
	fi

	if [[ -z "${nm_deb}" && -n "${nm_url}" ]]; then
		echo "[nomachine] Downloading package from NOMACHINE_DEB_URL"
		AptUpdate
		AptInstall curl ca-certificates
		nm_deb="/tmp/nomachine.deb"
		if ! DownloadFile "${nm_url}" "${nm_deb}"; then
			echo "[nomachine:ERROR] Failed to download from ${nm_url}" >&2
			if [[ "${nm_required}" == "1" ]]; then
				return 1
			fi
			return 0
		fi
	fi

	if [[ -z "${nm_deb}" ]]; then
		echo "[nomachine] No package found, skipping"
		echo "[nomachine] Hint: place *.deb under /tmp/overlay/packages/nomachine/ or set NOMACHINE_DEB_URL"
		if [[ "${nm_required}" == "1" ]]; then
			echo "[nomachine:ERROR] NOMACHINE_REQUIRED=1 but no package source found" >&2
			return 1
		fi
		return 0
	fi

	if ! dpkg-deb --info "${nm_deb}" >/dev/null 2>&1; then
		echo "[nomachine:ERROR] Invalid deb package: ${nm_deb}" >&2
		if [[ "${nm_required}" == "1" ]]; then
			return 1
		fi
		return 0
	fi

	echo "[nomachine] Installing package: ${nm_deb}"
	AptUpdate
	if ! AptInstall "${nm_deb}"; then
		echo "[nomachine:WARN] Initial install failed, trying dependency fix" >&2
		AptFixBrokenInstall
		if ! AptInstall "${nm_deb}"; then
			echo "[nomachine:ERROR] Installation failed" >&2
			if [[ "${nm_required}" == "1" ]]; then
				return 1
			fi
			return 0
		fi
	fi

	if systemctl list-unit-files | grep -q '^nxserver.service'; then
		systemctl enable nxserver.service 2>/dev/null || true
	fi

	echo "[nomachine] Installed successfully"
} # InstallOptionalNoMachine

InstallRuntimeDeploymentGuide() {
	local source_dir="/usr/local/share/opibot"
	local skel_dir="/etc/skel/Documents/OPiBot"
	local user home user_id group_id target_dir

	if [[ ! -d "${source_dir}" ]]; then
		echo "[doc:WARN] Missing OPiBot source directory: ${source_dir}" >&2
		return 0
	fi

	mkdir -p "${skel_dir}"
	rsync -a --exclude='.gitkeep' "${source_dir}/" "${skel_dir}/"
	chown -R root:root "${skel_dir}"
	echo "[doc] Synced OPiBot files into ${skel_dir}"

	for home in /home/*; do
		[[ -d "${home}" ]] || continue
		user="$(basename "${home}")"
		if ! getent passwd "${user}" >/dev/null 2>&1; then
			continue
		fi
		user_id="$(getent passwd "${user}" | cut -d: -f3)"
		group_id="$(getent passwd "${user}" | cut -d: -f4)"
		target_dir="${home}/Documents/OPiBot"
		mkdir -p "${target_dir}"
		rsync -a --exclude='.gitkeep' "${source_dir}/" "${target_dir}/"
		chown -R "${user_id}:${group_id}" "${target_dir}"
		echo "[doc] Synced OPiBot files for user ${user}"
	done
} # InstallRuntimeDeploymentGuide

# =========================
# Runtime tuning and system defaults
# =========================

InjectCm5CcOverlayHints() {
	local env_file="/boot/orangepiEnv.txt"
	local example_file="/boot/CM5-CC-overlays-example.txt"
	local marker_start="# BEGIN CM5-CC OVERLAY HINTS"
	local template_name="rk3588-opicm5-cc-default-overlays.txt"
	local kernel_template=""
	local candidate

	if [[ "${BOARD}" != "orangepicm5-cc" ]]; then
		return 0
	fi

	if [[ ! -f "${env_file}" ]]; then
		echo "[overlay-hints:WARN] ${env_file} not found, skip injecting hints" >&2
		return 0
	fi

	for candidate in \
		"/boot/dtb/rockchip/overlay/${template_name}" \
		"/boot/dtb-$(uname -r)/rockchip/overlay/${template_name}" \
		"/usr/lib/linux-image-current-rockchip-rk3588-rt/rockchip/overlay/${template_name}" \
		/usr/lib/linux-image-*/rockchip/overlay/"${template_name}"; do
		if [[ -r "${candidate}" ]]; then
			kernel_template="${candidate}"
			break
		fi
	done

	if [[ -z "${kernel_template}" ]]; then
		echo "[overlay-hints:WARN] Kernel template ${template_name} not found in image, using fallback example" >&2
	else
		echo "[overlay-hints] Using kernel template: ${kernel_template}"
	fi

	# ── 预置外设 overlay（官方 CM5-CC 基础组合，接口常驻；无外设接入无流量不报错）──
	# 来源: rk3588-opicm5-cc-default-overlays.txt（内核包官方模板）
	# can1-m1: 内置 CANFD (DroneCAN)；uart1-m1/uart6-m2/uart4-m2: UART 用户口；
	# spi1-m2: spidev；pwm-io: 外部 PWM3/PWM15；usb-net: USB host 端口
	# 相机: 载板默认 OV13855（官方支持: ov13855.c 驱动 + rk3588-ov13855-c1 overlay,
	# CSI D-PHY0 + I2C7）→ 预置 ov13855-c1（未接 sensor 时管线使能无数据流, 不报错）
	PRESET_OVERLAYS="opicm5-cc-usb-net opicm5-cc-wireless-sdio can1-m1 uart1-m1 uart6-m2 uart4-m2 opicm5-cc-pwm-io spi1-m2-cs0-spidev ov13855-c1"
	if grep -q '^overlays=' "${env_file}"; then
		if ! grep -q 'can1-m1' "${env_file}"; then
			sed -i "s|^overlays=.*|overlays=${PRESET_OVERLAYS}|" "${env_file}"
			echo "[overlay-hints] Replaced overlays= with preset: ${PRESET_OVERLAYS}"
		else
			echo "[overlay-hints] overlays= already contains preset, skip"
		fi
	else
		echo "overlay_prefix=rk3588" >> "${env_file}"
		echo "overlays=${PRESET_OVERLAYS}" >> "${env_file}"
		echo "[overlay-hints] Preset overlays= into ${env_file}: ${PRESET_OVERLAYS}"
	fi

	if ! grep -q "${marker_start}" "${env_file}"; then
		cat <<'EOF' >> "${env_file}"

# BEGIN CM5-CC OVERLAY HINTS
# CM5-CC Overlay Quick Guide
# 1) Keep only one active overlays= line.
# 2) overlay_prefix should stay rk3588.
# 3) Copy one overlays= line from /boot/CM5-CC-overlays-example.txt.
# 4) Reboot after editing.
#
# Notes:
# - Prefer opicm5-cc-cam1 for camera path.
# - Do not use uart2-m1 with sdmmc boot media; use uart2-m0 if UART2 is required.
# - Do not disable fan path or break PWM15 pinmux via overlays.
# END CM5-CC OVERLAY HINTS
EOF
		echo "[overlay-hints] Appended CM5-CC overlay hints into ${env_file}"
	else
		echo "[overlay-hints] Hints already present in ${env_file}, skip"
	fi

	if [[ -n "${kernel_template}" ]]; then
		{
			echo "# CM5-CC overlay template"
			echo "# Source: ${kernel_template}"
			echo "# Copy one overlays= line into /boot/orangepiEnv.txt and reboot."
			echo
			cat "${kernel_template}"
			echo
			echo "# Safety notes:"
			echo "# - Do not use uart2-m1 with sdmmc boot media; use uart2-m0 if UART2 is required."
			echo "# - Keep only one active overlays= line in /boot/orangepiEnv.txt."
		} > "${example_file}"
	else
		cat <<'EOF' > "${example_file}"
# CM5-CC overlay template (fallback)
# Kernel template file not found during image customization.
# Set overlay_prefix and a single overlays= line in /boot/orangepiEnv.txt, then reboot.

overlay_prefix=rk3588
overlays=opicm5-cc-usb-net can1-m1 uart1-m1 uart6-m2 uart4-m2 opicm5-cc-pwm-io spi1-m2-cs0-spidev
# 相机: 载板默认 OV13855 → ov13855-c1（CSI D-PHY0 + I2C7）
# 备选: opicm5-cc-cam1（RPi 模块 ov5647/imx219, I2C1）; ov13855-c2/c3（其他通道）
# 可选: opicm5-cc-lcd / opicm5-cc-audio-es8388 / opicm5-cc-pcie2x1l2 / opicm5-cc-wireless-sdio
# 注意: UART6 用 m2（官方默认），勿用 m1

# Safety notes:
# - Do not use uart2-m1 with sdmmc boot media; use uart2-m0 if UART2 is required.
# - Keep only one active overlays= line in /boot/orangepiEnv.txt.
EOF
	fi
	chmod 0644 "${example_file}"
	echo "[overlay-hints] Wrote ${example_file}"
} # InjectCm5CcOverlayHints

FixRuntimeRTTunePermissions() {
	local exec_entries=(
		"/usr/local/sbin/runtime-rt-tune|runtime-rt-tune script"
		"/usr/local/sbin/opibot-performance-mode|opibot-performance-mode script"
		"/usr/local/sbin/opibot-runtime-mode|opibot-runtime-mode script"
		"/usr/local/sbin/opibot-irq-layout|opibot-irq-layout script"
		"/usr/local/sbin/opibot-boot-profile-sync|opibot-boot-profile-sync script"
		"/usr/local/sbin/opibot-service-layout|opibot-service-layout script"
		"/usr/local/sbin/opibot-accel-healthcheck|opibot-accel-healthcheck script"
	)
	local readonly_entries=(
		"/etc/systemd/system/runtime-rt-tune.service|runtime-rt-tune unit"
		"/etc/systemd/system/opibot-performance-mode.service|opibot-performance-mode unit"
		"/etc/systemd/system/opibot-runtime-mode.service|opibot-runtime-mode unit"
		"/etc/systemd/system/opibot-performance-autoswitch.service|opibot-performance-autoswitch unit"
		"/etc/systemd/system/opibot-runtime-autoswitch.service|opibot-runtime-autoswitch unit"
		"/etc/systemd/system/opibot-irq-layout.service|opibot-irq-layout unit"
		"/etc/systemd/system/opibot-service-layout.service|opibot-service-layout unit"
		"/etc/systemd/system/opibot-accel-healthcheck.service|opibot-accel-healthcheck unit"
		"/etc/systemd/system/opibot-ros2-high-performance.service|opibot-ros2-high-performance unit"
		"/etc/systemd/system/opibot-ros2.target|opibot-ros2 target"
		"/etc/systemd/system/opibot-control-prepare.service|opibot-control-prepare unit"
		"/etc/systemd/system/opibot-perception-prepare.service|opibot-perception-prepare unit"
		"/etc/systemd/system/opibot-planning-prepare.service|opibot-planning-prepare unit"
		"/etc/systemd/system/opibot-base.target|opibot-base target"
		"/etc/systemd/system/opibot-control.target|opibot-control target"
		"/etc/systemd/system/opibot-perception.target|opibot-perception target"
		"/etc/systemd/system/opibot-planning.target|opibot-planning target"
		"/etc/systemd/system/opibot-mission.target|opibot-mission target"
		"/etc/systemd/system/opibot-control.slice|opibot-control slice"
		"/etc/systemd/system/opibot-perception.slice|opibot-perception slice"
		"/etc/systemd/system/opibot-planning.slice|opibot-planning slice"
		"/etc/systemd/system/opibot-support.slice|opibot-support slice"
		"/etc/default/opibot-performance-mode|opibot-performance-mode config"
		"/etc/default/opibot-boot-profile|opibot-boot-profile config"
		"/etc/default/opibot-runtime-mode|opibot-runtime-mode config"
		"/etc/default/opibot-irq-layout|opibot-irq-layout config"
		"/etc/default/opibot-service-layout|opibot-service-layout config"
	)
	local entry path label

	for entry in "${exec_entries[@]}"; do
		IFS='|' read -r path label <<< "${entry}"
		SetOwnerModeIfFileExists "${path}" "root:root" "0755" "${label}"
	done

	for entry in "${readonly_entries[@]}"; do
		IFS='|' read -r path label <<< "${entry}"
		SetOwnerModeIfFileExists "${path}" "root:root" "0644" "${label}"
	done
} # FixRuntimeRTTunePermissions

DisableDnsmasqByDefault() {
	if dpkg-query -W -f='${Status}' dnsmasq 2>/dev/null | grep -q "install ok installed"; then
		systemctl disable dnsmasq.service 2>/dev/null || true
		systemctl stop dnsmasq.service 2>/dev/null || true
		systemctl mask dnsmasq.service 2>/dev/null || true
		echo "Disabled dnsmasq.service to keep systemd-resolved as the default DNS stack"
	fi
} # DisableDnsmasqByDefault

RemoveConsoleAutologinOverrides() {
	local path
	for path in \
		/etc/systemd/system/getty@.service.d \
		/etc/systemd/system/serial-getty@.service.d \
		/lib/systemd/system/getty@.service.d \
		/lib/systemd/system/serial-getty@.service.d \
		/usr/lib/systemd/system/getty@.service.d \
		/usr/lib/systemd/system/serial-getty@.service.d
	do
		[[ -e "${path}" ]] || continue
		rm -rf "${path}"
	done

	systemctl daemon-reload || true
	echo "Removed CLI autologin overrides for getty and serial-getty"
} # RemoveConsoleAutologinOverrides

# =========================
# Boot/runtime policy orchestration
# =========================
# Robot onboard image installers (mirror rpicm5-auto-deploy modules)
# =========================

InstallTelemetryAgent() {
	local service="/etc/systemd/system/telemetry-agent.service"
	local agent_dir="/opt/telemetry-agent"

	if [[ ! -f "${service}" || ! -d "${agent_dir}" ]]; then
		echo "[telemetry:WARN] telemetry-agent missing (service=${service} dir=${agent_dir}); skipping" >&2
		return 0
	fi
	SetOwnerModeIfFileExists "${service}" "root:root" "0644" "telemetry-agent unit"
	systemctl daemon-reload
	systemctl enable telemetry-agent.service
	echo "[telemetry] telemetry-agent.service enabled (config: /etc/default/telemetry-agent)"
} # InstallTelemetryAgent

InstallCanSetup() {
	local script="/usr/local/sbin/can0-setup.sh"
	local service="/etc/systemd/system/can0-setup.service"

	if [[ -f "${script}" ]]; then
		SetOwnerModeIfFileExists "${script}" "root:root" "0755" "can0-setup script"
	fi
	if [[ -f "${service}" ]]; then
		SetOwnerModeIfFileExists "${service}" "root:root" "0644" "can0-setup unit"
		systemctl daemon-reload
		systemctl enable can0-setup.service
		echo "[can] can0-setup.service enabled (DroneCAN 1Mbit/s, restart-ms 100)"
	fi
} # InstallCanSetup

ConfigureRobotUserGroups() {
	local user groups group
	for user in /home/*; do
		[[ -d "${user}" ]] || continue
		user="$(basename "${user}")"
		getent passwd "${user}" >/dev/null 2>&1 || continue
		for group in docker dialout video gpio spi i2c render realtime; do
			if getent group "${group}" >/dev/null 2>&1; then
				if ! id -nG "${user}" 2>/dev/null | tr ' ' '\n' | grep -qx "${group}"; then
					if usermod -aG "${group}" "${user}"; then
						echo "[user] ${user} added to ${group}"
					fi
				fi
			fi
		done
	done
} # ConfigureRobotUserGroups

EnableDockerRobot() {
	if dpkg-query -W -f='${Status}' docker.io 2>/dev/null | grep -q "install ok installed"; then
		systemctl enable docker.service
		systemctl enable containerd.service 2>/dev/null || true
		echo "[docker] docker.service enabled"
	fi
	echo "[docker] containers are NOT staged in the image — pull robotics-containers at runtime (git clone <remote>/robotics-containers && bash build.sh)"
} # EnableDockerRobot

# =========================
# GPU / NPU acceleration (RK3588s: Mali-G610 Valhall + RKNPU 6 TOPS)
# =========================

InstallPipUser() {
	# 用户级 pip 安装（PEP 668 合规 + 统一规范：包装在默认用户的 ~/.local）
	# 用法: InstallPipUser <pkg...>   （幂等：已装则跳过）
	local robot_user="" home user
	for home in /home/*; do
		[[ -d "${home}" ]] || continue
		user="$(basename "${home}")"
		getent passwd "${user}" >/dev/null 2>&1 || continue
		robot_user="${user}"
		break
	done
	[[ -n "${robot_user}" ]] || robot_user="root"

	if runuser -u "${robot_user}" -- python3 -c "import importlib.util; exit(0 if all(importlib.util.find_spec(m) for m in '$*'.split()) else 1)" 2>/dev/null; then
		echo "[pip] $* already installed for ${robot_user}, skipping"
		return 0
	fi
	echo "[pip] Installing $* for user ${robot_user} (--user --break-system-packages)..."
	if ! runuser -u "${robot_user}" -- pip3 install --user --break-system-packages --no-cache-dir "$@"; then
		echo "[pip:ERROR] pip install $* FAILED for ${robot_user}" >&2
		return 1
	fi
	echo "[pip] $* installed for ${robot_user} (~/.local)"
} # InstallPipUser

InstallRknnRuntime() {
	# NPU user-space — unified install policy:
	#   REQUIRED  rknn-toolkit-lite2 (onboard Python inference, cp312 arm64
	#             wheel). Installed at BUILD time like apt packages; build
	#             already requires network (apt/sources), so a pip failure
	#             fails the build — no runtime fallback (runtime install is
	#             fragile on unattended robots).
	#   OPTIONAL  librknnrt C library (staged overlay/packages/rknn deb or
	#             RKNN_RUNTIME_URL) for C/C++ inference / containers — a
	#             capability enhancement, not a fallback path.

	# 1) lite2 — REQUIRED (build-time, like apt); user-level (PEP 668 compliant)
	if ! InstallPipUser rknn-toolkit-lite2; then
		echo "[rknn:ERROR] rknn-toolkit-lite2 install FAILED — build requires network (same as apt). Aborting." >&2
		return 1
	fi

	# 2) librknnrt — OPTIONAL capability (C/C++ inference / containers)
	local pkg_dir="/tmp/overlay/packages/rknn"
	local url="${RKNN_RUNTIME_URL:-}"
	local deb=""
	if [[ -d "${pkg_dir}" ]]; then
		deb="$(find "${pkg_dir}" -maxdepth 1 -type f -name '*.deb' | sort | head -n1)"
	fi
	if [[ -z "${deb}" && -n "${url}" ]]; then
		echo "[rknn] Downloading librknnrt (optional C runtime) from ${url}"
		AptUpdate
		AptInstall curl
		deb="/tmp/librknnrt.deb"
		if ! DownloadFile "${url}" "${deb}"; then
			echo "[rknn:WARN] librknnrt download failed — optional, skipping" >&2
			return 0
		fi
	fi
	if [[ -z "${deb}" ]]; then
		echo "[rknn] librknnrt C runtime skipped (optional; stage overlay/packages/rknn deb or set RKNN_RUNTIME_URL)"
		return 0
	fi

	AptUpdate
	if ! AptInstall "${deb}"; then
		echo "[rknn:WARN] librknnrt install failed — optional, skipping" >&2
		return 0
	fi
	echo "[rknn] librknnrt installed from ${deb} (C/C++ inference available)"
} # InstallRknnRuntime

InstallLibmali() {
	# Mali-G610 (Valhall) has NO open driver on 6.1 (panthor needs 6.10+,
	# panfrost is Bifrost-only) — rockchip libmali blob is the acceleration
	# path for desktop + container rviz2. Package source:
	#   1) /tmp/overlay/packages/mali/*.deb
	#   2) LIBMALI_URL (airockchip/libmali release deb)
	local pkg_dir="/tmp/overlay/packages/mali"
	local url="${LIBMALI_URL:-}"
	local deb=""

	if ldconfig -p 2>/dev/null | grep -q 'libmali'; then
		echo "[mali] libmali already installed, skipping"
		return 0
	fi
	if [[ -d "${pkg_dir}" ]]; then
		deb="$(find "${pkg_dir}" -maxdepth 1 -type f -name '*.deb' | sort | head -n1)"
	fi
	if [[ -z "${deb}" && -n "${url}" ]]; then
		AptUpdate
		AptInstall curl
		deb="/tmp/libmali.deb"
		if ! DownloadFile "${url}" "${deb}"; then
			echo "[mali:WARN] libmali download failed; GPU falls back to software rendering" >&2
			return 0
		fi
	fi
	if [[ -z "${deb}" ]]; then
		echo "[mali:WARN] No libmali package; set LIBMALI_URL or stage overlay/packages/mali/*.deb" >&2
		echo "[mali] Desktop/container GL falls back to llvmpipe (software)"
		return 0
	fi

	AptUpdate
	if ! AptInstall "${deb}"; then
		echo "[mali:WARN] libmali install failed; falling back to software rendering" >&2
		return 0
	fi
	echo "[mali] libmali installed from ${deb}"
} # InstallLibmali

InstallChronyRobot() {
	# chrony: guaranteed NTP sources for onboard timing (robot forensics).
	local conf="/etc/chrony/chrony.conf"
	[[ -f "${conf}" ]] || return 0
	cp -n "${conf}" "${conf}.bak" 2>/dev/null || true
	for line in "pool ntp.aliyun.com iburst" "pool ntp.tencent.com iburst" "pool 2.debian.pool.ntp.org iburst"; do
		if ! grep -qF "${line}" "${conf}" 2>/dev/null; then
			echo "${line}" >> "${conf}"
		fi
	done
	systemctl enable chrony 2>/dev/null || true
	echo "[chrony] NTP pools configured + chrony enabled"
} # InstallChronyRobot

InstallWifiProvision() {
	# 配网 Web 服务（opibot-cm5 AP 网段 10.42.0.1:80）——仅在 AP profile 存在时启用
	if [[ -f /etc/NetworkManager/system-connections/opibot-ap.nmconnection ]] \
		&& [[ -f /etc/systemd/system/wifi-provision.service ]] \
		&& [[ -f /opt/wifi-provision/provision-server.py ]]; then
		SetOwnerModeIfFileExists "/opt/wifi-provision/provision-server.py" "root:root" "0755" "provision-server"
		SetOwnerModeIfFileExists "/etc/systemd/system/wifi-provision.service" "root:root" "0644" "wifi-provision unit"
		systemctl daemon-reload
		systemctl enable wifi-provision.service
		echo "[wifi] wifi-provision.service enabled (http://10.42.0.1 配网; AP 保留 SSH)"
	else
		echo "[wifi:WARN] wifi-provision skipped (AP profile / unit / script missing)"
	fi
} # InstallWifiProvision

InstallRtVerifyService() {
	if [[ -f /etc/systemd/system/rt-verify.service ]]; then
		systemctl daemon-reload
		systemctl enable rt-verify.service
		echo "[rtverify] rt-verify.service enabled (boot self-check)"
	fi
} # InstallRtVerifyService

# =========================

ConfigureRTKernel() {
	# Setup RT kernel boot parameters for RT cores; files come from overlay
	# RK3588S (8-core: 4×A76 + 4×A55): CPUs 6,7 (A76) reserved for RT tasks
	local RT_CPUS="6,7"
	local BG_CPUS="0-5"
	local envfile="/boot/orangepiEnv.txt"
	local boot_profile_config="/etc/default/opibot-boot-profile"
	local mode_config="/etc/default/opibot-performance-mode"
	local boot_profile="rt-high-performance"
	local rt_bootargs="nohz_full=${RT_CPUS} rcu_nocbs=${RT_CPUS} isolcpus=managed,domain,${RT_CPUS} irqaffinity=${BG_CPUS}"

	echo "Configuring RT kernel tuning for board: ${BOARD}"

	# Compatibility path: read the legacy performance-mode file first,
	# then let the new boot-profile file override static boot settings.
	if [[ -f "${mode_config}" ]]; then
		# shellcheck disable=SC1090
		source "${mode_config}"
		RT_CPUS="${RT_CPUS:-${RT_CPUS}}"
		BG_CPUS="${BG_CPUS:-${BG_CPUS}}"
		boot_profile="${BOOT_PROFILE:-${boot_profile}}"
	fi

	if [[ -f "${boot_profile_config}" ]]; then
		# shellcheck disable=SC1090
		source "${boot_profile_config}"
		RT_CPUS="${CONTROL_CPUS:-${RT_CPUS}}"
		BG_CPUS="${SYSTEM_CPUS:-${BG_CPUS}}"
		boot_profile="${BOOT_PROFILE:-${boot_profile}}"
		rt_bootargs="nohz_full=${RT_CPUS} rcu_nocbs=${RT_CPUS} isolcpus=managed,domain,${RT_CPUS} irqaffinity=${BG_CPUS}"
	fi

	# 1. Add kernel boot parameters via orangepiEnv.txt extraargs.
	# Authority path: opibot-boot-profile-sync. The inline branch below is kept
	# only as a compatibility marker. Missing helper is now treated as a fatal
	# integration error so boot argument rendering stays single-sourced.
	if [[ -x /usr/local/sbin/opibot-boot-profile-sync ]]; then
		/usr/local/sbin/opibot-boot-profile-sync apply
	else
		echo "[rt:ERROR] Missing /usr/local/sbin/opibot-boot-profile-sync; refusing to render boot args via deprecated inline path" >&2
		return 1
	fi

	# 2. Enable runtime RT tuning service if present
	if [[ -f /etc/systemd/system/opibot-runtime-mode.service ]]; then
		FixRuntimeRTTunePermissions
		systemctl daemon-reload
		systemctl disable runtime-rt-tune.service 2>/dev/null || true
		systemctl disable opibot-performance-mode.service 2>/dev/null || true
		systemctl disable opibot-performance-autoswitch.service 2>/dev/null || true
		systemctl enable opibot-runtime-mode.service
		systemctl enable opibot-runtime-autoswitch.service 2>/dev/null || true
		systemctl enable opibot-irq-layout.service 2>/dev/null || true
		echo "Enabled opibot-runtime-mode.service"
	elif [[ -f /etc/systemd/system/opibot-performance-mode.service ]]; then
		FixRuntimeRTTunePermissions
		systemctl daemon-reload
		systemctl disable runtime-rt-tune.service 2>/dev/null || true
		systemctl enable opibot-performance-mode.service
		systemctl enable opibot-performance-autoswitch.service 2>/dev/null || true
		systemctl enable opibot-ros2-high-performance.service 2>/dev/null || true
		echo "Enabled opibot-performance-mode.service"
	elif [[ -f /etc/systemd/system/runtime-rt-tune.service ]]; then
		FixRuntimeRTTunePermissions
		systemctl daemon-reload
		systemctl enable runtime-rt-tune.service
		echo "Enabled runtime-rt-tune.service"
	else
		echo "WARNING: no RT performance mode service found; skipping enable"
	fi

	# 3. Create realtime group for RT application users
	if ! getent group realtime >/dev/null 2>&1; then
		groupadd -r realtime
		echo "Created 'realtime' group for RT priority permissions"
	fi

	echo "RT kernel boot params configured"
} # ConfigureRTKernel

# =========================
# Main flow
# =========================

Main() {
	# Exit immediately if any command fails
	set -e

	EnsureCustomizeImageContext

	echo "[main] Starting image customization for $RELEASE on $BOARD"

	# ========== CRITICAL: Overlay merge must succeed ==========
	# If overlay merge fails, the entire script will exit with error code 1
	echo "[main] Step 1: Merge overlay (CRITICAL)"
	if ! MergeOverlayToRoot; then
		echo "[main:FATAL] Overlay merge FAILED - aborting image customization" >&2
		exit 1
	fi
	echo "[main] Overlay merge SUCCESS, continuing..."

	# ========== Release-specific configuration ==========
	echo "[main] Step 2: Release-specific configuration for $RELEASE"
	echo "[main] Step 2a: Fix service defaults and install-time permissions"
	FixRuntimeRTTunePermissions
	DisableDnsmasqByDefault
	# Remove Armbian's hardcoded '--autologin orangepi' getty override — the
	# actual user is horizon (OPI_USERNAME); autologin to a nonexistent user
	# caused the boot login-failure loop. Console now prompts normally (SSH/
	# serial unaffected; desktop via lightdm).
	RemoveConsoleAutologinOverrides

	case $RELEASE in
		xenial)
			echo "[main] Xenial configuration (none)"
			;;
		stretch)
			echo "[main] Stretch configuration (none)"
			;;
		buster)
			echo "[main] Buster configuration (none)"
			;;
		bullseye)
			if [[ "${BUILD_RT_IMAGE}" == "yes" ]]; then
				echo "[main] Bullseye: Configuring RT kernel"
				ConfigureRTKernel
			fi
			;;
		bionic)
			echo "[main] Bionic configuration (none)"
			;;
		focal)
			if [[ "${BUILD_RT_IMAGE}" == "yes" ]]; then
				echo "[main] Focal: Configuring RT kernel"
				ConfigureRTKernel
			fi
			;;
		jammy)
			if [[ "${BUILD_RT_IMAGE}" == "yes" ]]; then
				echo "[main] Jammy: Configuring RT features"
				ConfigureRTKernel
			fi
			# Wi-Fi: handled by NM connection file in overlay
			# (etc/NetworkManager/system-connections/Master.nmconnection)
			echo "[main] Jammy: Installing mDNS"
			InstallMDNS
			echo "[main] Jammy: Installing ROS2 Humble"
			InstallROS2 humble
			echo "[main] Jammy: Installing OpenCV"
			InstallOpenCV
			echo "[main] Jammy: Installing DroneCAN tooling"
			InstallDroneCAN
			echo "[main] Jammy: Ensuring render group access for DRM NPU path"
			EnsureRenderGroupAccess
			echo "[main] Jammy: Installing acceleration healthcheck"
			InstallAccelHealthcheck || true
			if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
				echo "[main] Jammy: Installing optional NoMachine"
				InstallOptionalNoMachine
			fi
			;;
		noble)
			if [[ "${BUILD_RT_IMAGE}" == "yes" ]]; then
				echo "[main] Noble: Configuring RT features"
				ConfigureRTKernel
			fi
			# Wi-Fi: handled by NM connection file in overlay
			# (etc/NetworkManager/system-connections/Master.nmconnection)
			echo "[main] Noble: Installing mDNS"
			InstallMDNS
			if [[ "${INSTALL_ROS2_SYSTEM:-no}" == "yes" ]]; then
				echo "[main] Noble: Installing ROS2 Jazzy (system-level)"
				InstallROS2 jazzy
			else
				echo "[main] Noble: ROS2 system-level install SKIPPED (pure containerized; INSTALL_ROS2_SYSTEM=no)"
			fi
			if [[ "${INSTALL_OPENCV_SYSTEM:-no}" == "yes" ]]; then
				echo "[main] Noble: Installing OpenCV (system-level)"
				InstallOpenCV
			else
				echo "[main] Noble: OpenCV system-level install SKIPPED (vio container only; INSTALL_OPENCV_SYSTEM=no)"
			fi
			echo "[main] Noble: Installing DroneCAN tooling"
			InstallDroneCAN
			echo "[main] Noble: Ensuring render group access for DRM NPU path"
			EnsureRenderGroupAccess
			echo "[main] Noble: Installing acceleration healthcheck"
			InstallAccelHealthcheck || true
			echo "[main] Noble: Configuring robot user groups"
			ConfigureRobotUserGroups
			echo "[main] Noble: Installing chrony NTP config"
			InstallChronyRobot
			echo "[main] Noble: Installing WiFi provisioning service"
			InstallWifiProvision
			echo "[main] Noble: Installing RT verify self-check"
			InstallRtVerifyService
			echo "[main] Noble: Installing NPU runtime (rknn-toolkit-lite2, required)"
			InstallRknnRuntime
			echo "[main] Noble: Installing Mali GPU userspace (libmali)"
			InstallLibmali
			echo "[main] Noble: Installing telemetry agent"
			InstallTelemetryAgent
			echo "[main] Noble: Installing CAN setup service"
			InstallCanSetup
			echo "[main] Noble: Enabling Docker + robot stack"
			EnableDockerRobot
			if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
				echo "[main] Noble: Installing optional NoMachine"
				InstallOptionalNoMachine
			fi
			;;
		*)
			echo "[main:WARN] Unknown release: $RELEASE" >&2
			;;
	esac

	echo "[main] Step 3: Sync OPiBot files to user Documents"
	InstallRuntimeDeploymentGuide
	echo "[main] Step 4: Inject CM5-CC overlay hints (peripheral overlays preset)"
	InjectCm5CcOverlayHints

	echo "[main] ========== Image customization COMPLETE =========="
	echo "[main] All steps completed successfully"
} # Main

# =========================
# Legacy / optional paths
# =========================

InstallOpenMediaVault() {
	# use this routine to create a Debian based fully functional OpenMediaVault
	# image (OMV 3 on Jessie, OMV 4 with Stretch). Use of mainline kernel highly
	# recommended!
	#
	# Please note that this variant changes Orange Pi default security
	# policies since you end up with root password 'openmediavault' which
	# you have to change yourself later. SSH login as root has to be enabled
	# through OMV web UI first
	#
	# This routine is based on idea/code courtesy Benny Stark. For fixes,
	# discussion and feature requests please refer to
	# https://forum.armbian.com/index.php?/topic/2644-openmediavault-3x-customize-imagesh/

	echo root:openmediavault | chpasswd
	rm /root/.not_logged_in_yet
	. /etc/default/cpufrequtils
	export LANG=C LC_ALL="en_US.UTF-8"
	export DEBIAN_FRONTEND=noninteractive
	export APT_LISTCHANGES_FRONTEND=none

	case ${RELEASE} in
		jessie)
			OMV_Name="erasmus"
			OMV_EXTRAS_URL="https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/openmediavault-omvextrasorg_latest_all3.deb"
			;;
		stretch)
			OMV_Name="arrakis"
			OMV_EXTRAS_URL="https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/openmediavault-omvextrasorg_latest_all4.deb"
			;;
	esac

	# Add OMV source.list and Update System
	cat > /etc/apt/sources.list.d/openmediavault.list <<- EOF
	deb https://openmediavault.github.io/packages/ ${OMV_Name} main
	## Uncomment the following line to add software from the proposed repository.
	deb https://openmediavault.github.io/packages/ ${OMV_Name}-proposed main

	## This software is not part of OpenMediaVault, but is offered by third-party
	## developers as a service to OpenMediaVault users.
	# deb https://openmediavault.github.io/packages/ ${OMV_Name} partner
	EOF

	# Add OMV and OMV Plugin developer keys, add Cloudshell 2 repo for XU4
	if [ "${BOARD}" = "odroidxu4" ]; then
		add-apt-repository -y ppa:kyle1117/ppa
		sed -i 's/jessie/xenial/' /etc/apt/sources.list.d/kyle1117-ppa-jessie.list
	fi
	mount --bind /dev/null /proc/mdstat
	apt-get update
	apt-get --yes --force-yes --allow-unauthenticated install openmediavault-keyring
	apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 7AA630A1EDEE7D73
	apt-get update

	# install debconf-utils, postfix and OMV
	HOSTNAME="${BOARD}"
	debconf-set-selections <<< "postfix postfix/mailname string ${HOSTNAME}"
	debconf-set-selections <<< "postfix postfix/main_mailer_type string 'No configuration'"
	apt-get --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install \
		debconf-utils postfix
	# move newaliases temporarely out of the way (see Ubuntu bug 1531299)
	cp -p /usr/bin/newaliases /usr/bin/newaliases.bak && ln -sf /bin/true /usr/bin/newaliases
	sed -i -e "s/^::1         localhost.*/::1         ${HOSTNAME} localhost ip6-localhost ip6-loopback/" \
		-e "s/^127.0.0.1   localhost.*/127.0.0.1   ${HOSTNAME} localhost/" /etc/hosts
	sed -i -e "s/^mydestination =.*/mydestination = ${HOSTNAME}, localhost.localdomain, localhost/" \
		-e "s/^myhostname =.*/myhostname = ${HOSTNAME}/" /etc/postfix/main.cf
	apt-get --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install \
		openmediavault

	# install OMV extras, enable folder2ram and tweak some settings
	FILE=$(mktemp)
	wget "$OMV_EXTRAS_URL" -qO $FILE && dpkg -i $FILE

	/usr/sbin/omv-update
	# Install flashmemory plugin and netatalk by default, use nice logo for the latter,
	# tweak some OMV settings
	. /usr/share/openmediavault/scripts/helper-functions
	apt-get -y -q install openmediavault-netatalk openmediavault-flashmemory
	AFP_Options="mimic model = Macmini"
	SMB_Options="min receivefile size = 16384\nwrite cache size = 524288\ngetwd cache = yes\nsocket options = TCP_NODELAY IPTOS_LOWDELAY"
	xmlstarlet ed -L -u "/config/services/afp/extraoptions" -v "$(echo -e "${AFP_Options}")" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/smb/extraoptions" -v "$(echo -e "${SMB_Options}")" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/flashmemory/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/ssh/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/ssh/permitrootlogin" -v "0" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/time/ntp/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/time/timezone" -v "UTC" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/network/dns/hostname" -v "${HOSTNAME}" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/monitoring/perfstats/enable" -v "0" /etc/openmediavault/config.xml
	echo -e "OMV_CPUFREQUTILS_GOVERNOR=${GOVERNOR}" >>/etc/default/openmediavault
	echo -e "OMV_CPUFREQUTILS_MINSPEED=${MIN_SPEED}" >>/etc/default/openmediavault
	echo -e "OMV_CPUFREQUTILS_MAXSPEED=${MAX_SPEED}" >>/etc/default/openmediavault
	for i in netatalk samba flashmemory ssh ntp timezone interfaces cpufrequtils monit collectd rrdcached ; do
		/usr/sbin/omv-mkconf $i
	done
	/sbin/folder2ram -enablesystemd || true
	sed -i 's|-j /var/lib/rrdcached/journal/ ||' /etc/init.d/rrdcached

	# Fix multiple sources entry on ARM with OMV4
	sed -i '/stretch-backports/d' /etc/apt/sources.list

	# rootfs resize to 7.3G max and adding omv-initsystem to firstrun -- q&d but shouldn't matter
	echo 15500000s >/root/.rootfs_resize
	sed -i '/systemctl\ disable\ orangepi-firstrun/i \
	mv /usr/bin/newaliases.bak /usr/bin/newaliases \
	export DEBIAN_FRONTEND=noninteractive \
	sleep 3 \
	apt-get install -f -qq python-pip python-setuptools || exit 0 \
	pip install -U tzupdate \
	tzupdate \
	read TZ </etc/timezone \
	/usr/sbin/omv-initsystem \
	xmlstarlet ed -L -u "/config/system/time/timezone" -v "${TZ}" /etc/openmediavault/config.xml \
	/usr/sbin/omv-mkconf timezone \
	lsusb | egrep -q "0b95:1790|0b95:178a|0df6:0072" || sed -i "/ax88179_178a/d" /etc/modules' /usr/lib/orangepi/orangepi-firstrun
	sed -i '/systemctl\ disable\ orangepi-firstrun/a \
	sleep 30 && sync && reboot' /usr/lib/orangepi/orangepi-firstrun

	# add USB3 Gigabit Ethernet support
	echo -e "r8152\nax88179_178a" >>/etc/modules

	case ${BOARD} in
		odroidxu4)
			HMP_Fix='; taskset -c -p 4-7 $i '
			# Cloudshell stuff (fan, lcd, missing serials on 1st CS2 batch)
			echo "H4sIAKdXHVkCA7WQXWuDMBiFr+eveOe6FcbSrEIH3WihWx0rtVbUFQqCqAkYGhJn
			tF1x/vep+7oebDfh5DmHwJOzUxwzgeNIpRp9zWRegDPznya4VDlWTXXbpS58XJtD
			i7ICmFBFxDmgI6AXSLgsiUop54gnBC40rkoVA9rDG0SHHaBHPQx16GN3Zs/XqxBD
			leVMFNAz6n6zSWlEAIlhEw8p4xTyFtwBkdoJTVIJ+sz3Xa9iZEMFkXk9mQT6cGSQ
			QL+Cr8rJJSmTouuuRzfDtluarm1aLVHksgWmvanm5sbfOmY3JEztWu5tV9bCXn4S
			HB8RIzjoUbGvFvPw/tmr0UMr6bWSBupVrulY2xp9T1bruWnVga7DdAqYFgkuCd3j
			vORUDQgej9HPJxmDDv+3WxblBSuYFH8oiNpHz8XvPIkU9B3JVCJ/awIAAA==" \
			| tr -d '[:blank:]' | base64 --decode | gunzip -c >/usr/local/sbin/cloudshell2-support.sh
			chmod 755 /usr/local/sbin/cloudshell2-support.sh
			apt install -y i2c-tools odroid-cloudshell cloudshell2-fan
			sed -i '/systemctl\ disable\ orangepi-firstrun/i \
			lsusb | grep -q -i "05e3:0735" && sed -i "/exit\ 0/i echo 20 > /sys/class/block/sda/queue/max_sectors_kb" /etc/rc.local \
			/usr/sbin/i2cdetect -y 1 | grep -q "60: 60" && /usr/local/sbin/cloudshell2-support.sh' /usr/lib/orangepi/orangepi-firstrun
			;;
		bananapim3|nanopifire3|nanopct3plus|nanopim3)
			HMP_Fix='; taskset -c -p 4-7 $i '
			;;
		edge*|ficus|firefly-rk3399|nanopct4|nanopim4|nanopineo4|renegade-elite|roc-rk3399-pc|rockpro64)
			HMP_Fix='; taskset -c -p 4-5 $i '
			;;
	esac
	echo "* * * * * root for i in \`pgrep \"ftpd|nfsiod|smbd|afpd|cnid\"\` ; do ionice -c1 -p \$i ${HMP_Fix}; done >/dev/null 2>&1" \
		>/etc/cron.d/make_nas_processes_faster
	chmod 600 /etc/cron.d/make_nas_processes_faster

	# add SATA port multiplier hint if appropriate
	[ "${LINUXFAMILY}" = "sunxi" ] && \
		echo -e "#\n# If you want to use a SATA PM add \"ahci_sunxi.enable_pmp=1\" to bootargs above" \
		>>/boot/boot.cmd

	# Filter out some log messages
	echo ':msg, contains, "do ionice -c1" ~' >/etc/rsyslog.d/omv-orangepi.conf
	echo ':msg, contains, "action " ~' >>/etc/rsyslog.d/omv-orangepi.conf
	echo ':msg, contains, "netsnmp_assert" ~' >>/etc/rsyslog.d/omv-orangepi.conf
	echo ':msg, contains, "Failed to initiate sched scan" ~' >>/etc/rsyslog.d/omv-orangepi.conf

	# Fix little python bug upstream Debian 9 obviously ignores
	if [ -f /usr/lib/python3.5/weakref.py ]; then
		wget -O /usr/lib/python3.5/weakref.py \
		https://raw.githubusercontent.com/python/cpython/9cd7e17640a49635d1c1f8c2989578a8fc2c1de6/Lib/weakref.py
	fi

	# clean up and force password change on first boot
	umount /proc/mdstat
	chage -d 0 root
} # InstallOpenMediaVault

UnattendedStorageBenchmark() {
	# Function to create Orange Pi images ready for unattended storage performance testing.
	# Useful to use the same OS image with a bunch of different SD cards or eMMC modules
	# to test for performance differences without wasting too much time.

	rm /root/.not_logged_in_yet

	apt-get -qq install time

	wget -qO /usr/local/bin/sd-card-bench.sh https://raw.githubusercontent.com/ThomasKaiser/sbc-bench/master/sd-card-bench.sh
	chmod 755 /usr/local/bin/sd-card-bench.sh

	sed -i '/^exit\ 0$/i \
	/usr/local/bin/sd-card-bench.sh &' /etc/rc.local
} # UnattendedStorageBenchmark

InstallAdvancedDesktop()
{
	apt-get install -yy transmission libreoffice libreoffice-style-tango meld remmina thunderbird kazam avahi-daemon
	[[ -f /usr/share/doc/avahi-daemon/examples/sftp-ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/sftp-ssh.service /etc/avahi/services/
	[[ -f /usr/share/doc/avahi-daemon/examples/ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/ssh.service /etc/avahi/services/
	apt clean
} # InstallAdvancedDesktop

Main "$@"
