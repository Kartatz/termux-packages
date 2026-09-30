# shellcheck shell=bash
# This provides an utility to run binaries under termux environment via proot.
termux_setup_proot() {
	local TERMUX_PROOT_VERSION=5.3.0
	local TERMUX_PROOT_BIN="$TERMUX_COMMON_CACHEDIR/proot-bin-$TERMUX_ARCH"
	local TERMUX_PROOT_QEMU=""
	local TERMUX_PROOT_BIN_NAME="termux-proot-run"

	export PATH="$TERMUX_PROOT_BIN:$PATH"

	[[ -d "$TERMUX_PROOT_BIN" ]] && return

	if ! [[ -d "$TERMUX_PREFIX/opt/aosp" ]]; then
		echo "ERROR: Add 'aosp-libs' to TERMUX_PKG_BUILD_DEPENDS. 'proot' cannot run without it."
		exit 1
	fi

	mkdir -p "$TERMUX_PROOT_BIN"

	termux_download https://github.com/proot-me/proot/releases/download/v"$TERMUX_PROOT_VERSION"/proot-v"$TERMUX_PROOT_VERSION"-x86_64-static \
		"$TERMUX_PROOT_BIN/proot" \
		d1eb20cb201e6df08d707023efb000623ff7c10d6574839d7bb42d0adba6b4da
	chmod +x "$TERMUX_PROOT_BIN"/proot

	if [[ "$TERMUX_ARCH" == "aarch64" ]] || [[ "$TERMUX_ARCH" == "arm" ]]; then
		# The multiarch release is based on QEMU 7.2, whose TCG crashes
		# on the multi-threaded external interpreter of GHC with an
		# assertion in cpu_exec. The current Ubuntu release dropped the
		# statically linked package, so use the last LTS that has it.
		UBUNTU_RELEASE=noble DESTINATION="$TERMUX_PROOT_BIN" \
			termux_download_ubuntu_packages qemu-user-static
		mv "$TERMUX_PROOT_BIN"/usr/bin/qemu-"${TERMUX_ARCH/i686/i386}"-static \
			"$TERMUX_PROOT_BIN"/qemu-"$TERMUX_ARCH"
		rm -Rf "$TERMUX_PROOT_BIN"/usr
		chmod +x "$TERMUX_PROOT_BIN"/qemu-"$TERMUX_ARCH"
		TERMUX_PROOT_QEMU="-q $TERMUX_PROOT_BIN/qemu-$TERMUX_ARCH"
	fi

	# The binaries run through proot link against the GCC runtime, whose
	# libraries are only available in the toolchain directory. Expose
	# them alone through a dedicated search path: the toolchain directory
	# also holds the linker stubs of bionic, which must not shadow the
	# real system libraries.
	local _gcc_lib=""
	_gcc_lib="$(find "${TERMUX_COMMON_CACHEDIR}/android-gcc-cross" -maxdepth 3 -path "*android${TERMUX_PKG_API_LEVEL}/lib" -print -quit 2>/dev/null | head -n1)"
	if [ -n "${_gcc_lib}" ]; then
		mkdir -p "$TERMUX_PROOT_BIN/lib"
		for _gcc_runtime_lib in libssp.so libestdc++.so libgcc_s.so libegcc.so; do
			[ -f "${_gcc_lib}/${_gcc_runtime_lib}" ] && \
				ln -sf "${_gcc_lib}/${_gcc_runtime_lib}" "$TERMUX_PROOT_BIN/lib/${_gcc_runtime_lib}"
		done
	fi

	# NOTE: We include current PATH too so that host binaries also become available under proot.
	cat <<-EOF >"$TERMUX_PROOT_BIN/$TERMUX_PROOT_BIN_NAME"
		#!/bin/bash
		env -i \
			PATH="$TERMUX_PREFIX/bin:$PATH" \
			ANDROID_DATA=/data \
			ANDROID_ROOT=/system \
			HOME=$TERMUX_ANDROID_HOME \
			LANG=en_US.UTF-8 \
			PREFIX=$TERMUX_PREFIX \
			TERM=$TERM \
			TZ=UTC \
			LD_LIBRARY_PATH="$TERMUX_PROOT_BIN/lib:$TERMUX_PREFIX/lib" \
			$TERMUX_PROOT_EXTRA_ENV_VARS \
			$TERMUX_PROOT_BIN/proot $TERMUX_PROOT_QEMU -R / \
			-b "$TERMUX_PREFIX/opt/aosp:/system" \
			"\$@"
	EOF
	chmod +x "$TERMUX_PROOT_BIN/$TERMUX_PROOT_BIN_NAME"
}
