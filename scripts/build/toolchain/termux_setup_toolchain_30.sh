termux_patch_ndk_with_gcc_cross() {
	local _gcc_cross_dir="${TERMUX_COMMON_CACHEDIR}/android-gcc-cross"
	local _gcc_cross_stamp="${_gcc_cross_dir}/.termux-patches-applied-v5"
	if [ ! -x "${_gcc_cross_dir}/bin/ndk-patch" ] || [ ! -f "${_gcc_cross_stamp}" ]; then
		local _gcc_cross_tar="${_gcc_cross_dir}.tar.xz"
		local _gcc_cross_patch="${TERMUX_COMMON_CACHEDIR}/android-gcc-cross-0001-Termux-patches.patch"
		termux_download \
			"https://github.com/AmanoTeam/android-gcc-cross/releases/latest/download/x86_64-unknown-linux-gnu.tar.xz" \
			"${_gcc_cross_tar}"
		termux_download \
			"https://raw.githubusercontent.com/AmanoTeam/android-gcc-cross/refs/heads/master/patches/0001-Termux-patches.patch" \
			"${_gcc_cross_patch}"
		rm -Rf "${_gcc_cross_dir}"
		tar -xJf "${_gcc_cross_tar}" -C "${TERMUX_COMMON_CACHEDIR}"
		rm -f "${_gcc_cross_tar}"
		# The Termux patches also need to be applied on the bionic headers
		# bundled inside the GCC toolchain: the ndk-patches applied by
		# termux_setup_toolchain_30 only affect the NDK sysroot used by Clang,
		# while the GCC drivers compile against the toolchain's own copy of them.
		patch --silent -p1 -d "${_gcc_cross_dir}/include" < "${_gcc_cross_patch}"
		# Remove headers that are provided by Termux packages instead of
		# the ones bundled in the GCC toolchain, mirroring the removals
		# applied to the NDK sysroot below. The GCC drivers (and Clang,
		# through the ndk-patched wrappers) compile against the toolchain's
		# own copy of the bionic headers, so those removals are needed
		# here as well. The whole `unicode` directory is removed since it
		# is a superset of the unicode headers removed from the NDK
		# sysroot. <execinfo.h> is removed too since the backtrace(3)
		# functions it declares are only provided by bionic from API level
		# 33, so packages must not detect them at the default level.
		# <glob.h>, <iconv.h>, <spawn.h>, <sys/capability.h>, <sys/sem.h>
		# and <sys/shm.h> are kept: the functions they declare are provided
		# by bionic itself at the default API level (>= 24), so removing
		# them would break packages whose configure scripts detect those
		# functions (e.g. libx11, binutils), and the versions provided by
		# the Termux packages shadowing them, when they are dependencies,
		# take precedence through the prefix include dir anyway.
		rm -Rf "${_gcc_cross_dir}"/include/unicode \
			"${_gcc_cross_dir}"/include/{EGL,GLES{,2,3},vulkan} \
			"${_gcc_cross_dir}"/include/execinfo.h \
			"${_gcc_cross_dir}"/include/KHR/khrplatform.h
		# Refresh the compiler wrappers with the ones built from the
		# current obggcc master: the ones shipped in the tarball forward
		# bare Clang invocations without --target to the first Clang
		# found in PATH, which is the toolchain itself, hanging forever.
		# A host PATH is required: the build environment puts the
		# toolchain first in PATH, where there is no cc for make.
		env PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
			bash "${_gcc_cross_dir}/bin/update-wrapper" >/dev/null 2>&1
		# Define O_BINARY and O_TEXT like Gnulib does, since the GNU
		# tools expect them to exist when wrapping <fcntl.h>: unlike
		# Clang, the toolchain's include directories come first, so
		# generated wrapper headers cannot provide the definitions.
		local _fcntl
		while IFS= read -r -d '' _fcntl; do
			if ! grep -q "define O_BINARY" "${_fcntl}"; then
				printf '\n#ifndef O_BINARY\n#define O_BINARY 0\n#endif\n#ifndef O_TEXT\n#define O_TEXT 0\n#endif\n' >> "${_fcntl}"
			fi
		done < <(find "${_gcc_cross_dir}" -name fcntl.h -type f -print0)
		touch "${_gcc_cross_stamp}"
	fi
	rm -Rf "${_gcc_cross_dir}/include/zlib.h" "${_gcc_cross_dir}/include/zconf.h"
	rm -Rf "${_gcc_cross_dir}"/lib/libz.a "${_gcc_cross_dir}"/lib/libz.so \
		"${_gcc_cross_dir}"/lib/nouzen/libz.a "${_gcc_cross_dir}"/lib/nouzen/libz.so
	rm -Rf "${_gcc_cross_dir}"/*/lib/libz.a "${_gcc_cross_dir}"/*/lib/libz.so \
		"${_gcc_cross_dir}"/*/lib/static/libz.a "${_gcc_cross_dir}"/*/lib/static/libz.so \
		"${_gcc_cross_dir}"/*/lib/nouzen/lib/libz.a "${_gcc_cross_dir}"/*/lib/nouzen/lib/libz.so

	# The shared libgcc shipped by android-gcc-cross references
	# dl_iterate_phdr without a version while its other libc imports are
	# versioned, which the undefined symbols check in termux_step_massage
	# rejects in every package shipping it. Version the reference against
	# libc, like the rest of the imports.
	while IFS= read -r -d '' _libegcc; do
		python3 - "${_libegcc}" <<'PY'
import struct, sys

def cstr(data, off):
	end = data.index(b'\0', off)
	return data[off:end].decode()

path = sys.argv[1]
with open(path, 'rb') as f:
	data = bytearray(f.read())

if data[:4] != b'\x7fELF' or data[6] != 1:
	sys.exit(0)
is64 = data[4] == 2
if is64:
	e_shoff = struct.unpack_from('<Q', data, 0x28)[0]
	e_shentsize = struct.unpack_from('<H', data, 0x3a)[0]
	e_shnum = struct.unpack_from('<H', data, 0x3c)[0]
	e_shstrndx = struct.unpack_from('<H', data, 0x3e)[0]
	fmt, entsz = '<IIQQQQIIQQ', 64
else:
	e_shoff = struct.unpack_from('<I', data, 0x20)[0]
	e_shentsize = struct.unpack_from('<H', data, 0x2e)[0]
	e_shnum = struct.unpack_from('<H', data, 0x30)[0]
	e_shstrndx = struct.unpack_from('<H', data, 0x32)[0]
	fmt, entsz = '<IIIIIIIIII', 40

sh = [struct.unpack_from(fmt, data, e_shoff + i * e_shentsize) for i in range(e_shnum)]
stroff = sh[e_shstrndx][4]
secs = {}
for s in sh:
	end = data.index(b'\0', stroff + s[0])
	secs[data[stroff + s[0]:end].decode()] = s

vr = secs.get('.gnu.version_r')
dynstr = secs.get('.dynstr')
veridx = None
if vr and dynstr:
	off, stop, doff = vr[4], vr[4] + vr[5], dynstr[4]
	while off < stop:
		vn_version, vn_cnt, vn_file, vn_aux, vn_next = struct.unpack_from('<HHIII', data, off)
		fname = cstr(data, doff + vn_file)
		aux = off + vn_aux
		for _ in range(vn_cnt):
			vna_hash, vna_flags, vna_other, vna_name, vna_next = struct.unpack_from('<IHHII', data, aux)
			if fname == 'libc.so' and cstr(data, doff + vna_name) == 'LIBC':
				veridx = vna_other
			if not vna_next:
				break
			aux += vna_next
		if not vn_next:
			break
		off += vn_next

dynsym = secs.get('.dynsym')
gnuver = secs.get('.gnu.version')
patched = 0
if veridx and dynsym and dynstr and gnuver:
	soff, doff, voff = dynsym[4], dynstr[4], gnuver[4]
	sentsz = dynsym[9] or (24 if is64 else 16)
	for i in range(dynsym[5] // sentsz):
		nm, = struct.unpack_from('<I', data, soff + i * sentsz)
		name = cstr(data, doff + nm)
		ver, = struct.unpack_from('<H', data, voff + i * 2)
		if name == 'dl_iterate_phdr' and ver == 0:
			struct.pack_into('<H', data, voff + i * 2, veridx)
			patched += 1

if patched:
	with open(path, 'wb') as f:
		f.write(data)
	print(f"versioned {patched} dl_iterate_phdr reference(s) in {path}")
PY
	done < <(find "${_gcc_cross_dir}" -path '*/lib/gcc/libegcc.so' -print0)
	# ndk-patch prefers ANDROID_HOME/ANDROID_SDK_ROOT over ANDROID_NDK,
	# so blank them out to make it patch the overlay toolchain instead of
	# the read-only lowerdir (NDK), which the overlay would not pick up.
	ANDROID_HOME= ANDROID_SDK_ROOT= ANDROID_NDK_HOME= ANDROID_NDK_ROOT= NDK_HOME= \
		ANDROID_NDK="${TERMUX_STANDALONE_TOOLCHAIN}" "${_gcc_cross_dir}/bin/ndk-patch"
}

termux_setup_toolchain_30() {
	export PINO_WERROR=false
	export PINO_OPT_LEVEL=2
	export CFLAGS=""
	export CPPFLAGS=""
	export LDFLAGS="-L${TERMUX__PREFIX__LIB_DIR}"

	export AS=$TERMUX_HOST_PLATFORM-clang
	export CC=$TERMUX_HOST_PLATFORM-clang
	export CPP=$TERMUX_HOST_PLATFORM-cpp
	export CXX=$TERMUX_HOST_PLATFORM-clang++
	export LD=ld.lld
	export AR=llvm-ar
	export OBJCOPY=llvm-objcopy
	export OBJDUMP=llvm-objdump
	export RANLIB=llvm-ranlib
	export READELF=llvm-readelf
	export STRIP=llvm-strip
	export NM=llvm-nm
	export CXXFILT=llvm-cxxfilt

	export TERMUX_GHC_OPTIMISATION="-O"
	if [ "${TERMUX_DEBUG_BUILD}" = true ]; then
		TERMUX_GHC_OPTIMISATION="-O0"
	fi

	if [ "$TERMUX_ON_DEVICE_BUILD" = "false" ]; then
		export PATH=$TERMUX_STANDALONE_TOOLCHAIN/bin:$PATH
		export CC_FOR_BUILD=gcc
		export PKG_CONFIG=$TERMUX_STANDALONE_TOOLCHAIN/bin/pkg-config
		export PKGCONFIG=$PKG_CONFIG
		export CCTERMUX_HOST_PLATFORM=$TERMUX_HOST_PLATFORM$TERMUX_PKG_API_LEVEL
		if [ $TERMUX_ARCH = arm ]; then
			CCTERMUX_HOST_PLATFORM=armv7a-linux-androideabi$TERMUX_PKG_API_LEVEL
		fi
		LDFLAGS+=" -Wl,-rpath=$TERMUX__PREFIX__LIB_DIR -Wl,-rpath-link=$TERMUX__PREFIX__LIB_DIR"
	else
		export CC_FOR_BUILD=$CC
		# Some build scripts use environment variable 'PKG_CONFIG', so
		# using this for on-device builds too.
		export PKG_CONFIG=pkg-config
	fi
	export PKG_CONFIG_LIBDIR="$TERMUX_PKG_CONFIG_LIBDIR"

	if [ "$TERMUX_ARCH" = "arm" ]; then
		# https://developer.android.com/ndk/guides/standalone_toolchain.html#abi_compatibility:
		# "We recommend using the -mthumb compiler flag to force the generation of 16-bit Thumb-2 instructions".
		# With r13 of the ndk ruby 2.4.0 segfaults when built on arm with clang without -mthumb.
		CFLAGS+=" -march=armv7-a -mfpu=neon -mfloat-abi=softfp -mthumb"
		LDFLAGS+=" -march=armv7-a"
		export GOARCH=arm
		export GOARM=7
	elif [ "$TERMUX_ARCH" = "i686" ]; then
		# From $NDK/docs/CPU-ARCH-ABIS.html:
		CFLAGS+=" -march=i686 -msse3 -mstackrealign -mfpmath=sse"
		# i686 seem to explicitly require -fPIC, see
		# https://github.com/termux/termux-packages/issues/7215#issuecomment-906154438
		CFLAGS+=" -fPIC"
		export GOARCH=386
		export GO386=sse2
	elif [ "$TERMUX_ARCH" = "aarch64" ]; then
		export GOARCH=arm64
	elif [ "$TERMUX_ARCH" = "x86_64" ]; then
		export GOARCH=amd64
	else
		termux_error_exit "Invalid arch '$TERMUX_ARCH' - support arches are 'arm', 'i686', 'aarch64', 'x86_64'"
	fi

	# Android 7 started to support DT_RUNPATH (but not DT_RPATH).
	LDFLAGS+=" -Wl,--enable-new-dtags"

	# Avoid linking extra (unneeded) libraries.
	LDFLAGS+=" -Wl,--as-needed"

	# Basic hardening.
	CFLAGS+=" -fstack-protector-strong"
	LDFLAGS+=" -Wl,-z,relro,-z,now"

	if [ "$TERMUX_DEBUG_BUILD" = "true" ]; then
		CFLAGS+=" -g3 -O1"
		CPPFLAGS+=" -D_FORTIFY_SOURCE=2 -D__USE_FORTIFY_LEVEL=2"
	else
		CFLAGS+=" -Oz"
	fi

	export CXXFLAGS="$CFLAGS"
	# set the proper header include order - first package includes, then prefix includes
	# -isystem${TERMUX__PREFIX__BASE_INCLUDE_DIR}/c++/v1 is needed here for on-device building to work correctly
	export CPPFLAGS+=" -isystem${TERMUX__PREFIX__BASE_INCLUDE_DIR}/c++/v1 -isystem${TERMUX__PREFIX__INCLUDE_DIR}"
	if [ "$TERMUX_ARCH" != "$TERMUX_REAL_ARCH" ]; then
		export CPPFLAGS+=" -isystem${TERMUX__PREFIX__BASE_INCLUDE_DIR}"
	fi

	# If libandroid-support is declared as a dependency, link to it explicitly:
	if [ "$TERMUX_PKG_DEPENDS" != "${TERMUX_PKG_DEPENDS/libandroid-support/}" ]; then
		LDFLAGS+=" -Wl,--no-as-needed,-landroid-support,--as-needed"
	fi

	export GOOS=android
	export CGO_ENABLED=1
	export GO_LDFLAGS="-extldflags=-pie"
	export CGO_LDFLAGS="${LDFLAGS/ -Wl,-z,relro,-z,now/}"
	export CGO_CFLAGS="-isystem${TERMUX__PREFIX__INCLUDE_DIR}"
	if [ "$TERMUX_ARCH" != "$TERMUX_REAL_ARCH" ]; then
		export CGO_CFLAGS+=" -isystem${TERMUX__PREFIX__BASE_INCLUDE_DIR}"
	fi

	export CARGO_TARGET_NAME="${TERMUX_ARCH}-linux-android"
	if [[ "${TERMUX_ARCH}" == "arm" ]]; then
		CARGO_TARGET_NAME="armv7-linux-androideabi"
	fi
	local env_host="${CARGO_TARGET_NAME//-/_}"
	export CARGO_TARGET_${env_host@U}_LINKER="${CC}"
	export CARGO_TARGET_${env_host@U}_RUSTFLAGS="-L${TERMUX__PREFIX__LIB_DIR} -C link-arg=-Wl,-rpath=${TERMUX__PREFIX__LIB_DIR} -C link-arg=-Wl,--enable-new-dtags -C link-arg=-lestdc++"
	if [ "$TERMUX_ARCH" = "aarch64" ]; then
		# The link-time libc stubs do not provide the LSE atomic
		# helpers that GCC outlines atomics to, so keep them inline
		# like the NDK Clang compilers do.
		export CFLAGS_${env_host}="${CPPFLAGS} ${CFLAGS} -mno-outline-atomics"
		export CXXFLAGS_${env_host}="${CPPFLAGS} ${CXXFLAGS} -mno-outline-atomics"
	else
		export CFLAGS_${env_host}="${CPPFLAGS} ${CFLAGS}"
		export CXXFLAGS_${env_host}="${CPPFLAGS} ${CXXFLAGS}"
	fi
	export CC_x86_64_unknown_linux_gnu="gcc"
	export CFLAGS_x86_64_unknown_linux_gnu="-O2"
	export PKG_CONFIG_x86_64_unknown_linux_gnu="/usr/bin/pkg-config"
	export PKG_CONFIG_LIBDIR_x86_64_unknown_linux_gnu="/usr/lib/pkgconfig"
	export RUST_BACKTRACE="full"

	export ac_cv_func_getpwent=no
	export ac_cv_func_endpwent=yes
	export ac_cv_func_getpwnam=no
	export ac_cv_func_getpwuid=no
	export ac_cv_func_sigsetmask=no
	export ac_cv_c_bigendian=no

	if [ "$TERMUX_ON_DEVICE_BUILD" = "true" ]; then
		return
	fi

	[ -d "$TERMUX_STANDALONE_TOOLCHAIN" ] || mkdir -p "$TERMUX_STANDALONE_TOOLCHAIN"
	[ -d "${TERMUX_STANDALONE_TOOLCHAIN}-upper" ] || mkdir -p "${TERMUX_STANDALONE_TOOLCHAIN}-upper"
	[ -d "${TERMUX_STANDALONE_TOOLCHAIN}-work" ] || mkdir -p "${TERMUX_STANDALONE_TOOLCHAIN}-work"


	if ! mountpoint -q "${TERMUX_STANDALONE_TOOLCHAIN}"; then
		fuse-overlayfs \
			"${TERMUX_STANDALONE_TOOLCHAIN}" \
			-o lowerdir="${NDK}/toolchains/llvm/prebuilt/linux-x86_64" \
			-o upperdir="${TERMUX_STANDALONE_TOOLCHAIN}-upper" \
			-o workdir="${TERMUX_STANDALONE_TOOLCHAIN}-work"
	fi

	if [ -f "${TERMUX_STANDALONE_TOOLCHAIN}/.termux-standalone-toolchain" ]; then
		termux_patch_ndk_with_gcc_cross
		return
	fi

	local _NDK_ARCHNAME=$TERMUX_ARCH
	if [ "$TERMUX_ARCH" = "aarch64" ]; then
		_NDK_ARCHNAME=arm64
	elif [ "$TERMUX_ARCH" = "i686" ]; then
		_NDK_ARCHNAME=x86
	fi
	cp $NDK/source.properties $TERMUX_STANDALONE_TOOLCHAIN/
	# Remove android-support header wrapping not needed on android-21:
	rm -Rf $TERMUX_STANDALONE_TOOLCHAIN/sysroot/usr/local

	for HOST_PLAT in aarch64-linux-android armv7a-linux-androideabi i686-linux-android x86_64-linux-android; do
		cp $TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT$TERMUX_PKG_API_LEVEL-clang \
			$TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT-clang
		cp $TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT$TERMUX_PKG_API_LEVEL-clang++ \
			$TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT-clang++

		cp $TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT$TERMUX_PKG_API_LEVEL-clang \
			$TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT-cpp
		sed -i 's|"$bin_dir/clang"|& -E|' \
			$TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT-cpp

		cp $TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT-clang \
			$TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT-gcc
		cp $TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT-clang++ \
			$TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT-g++
		sed -i '1a\[ "$1" = "-dumpversion" ] \&\& set -- -dumpfullversion "$@"' \
			$TERMUX_STANDALONE_TOOLCHAIN/bin/$HOST_PLAT-gcc
	done

	cp $TERMUX_STANDALONE_TOOLCHAIN/bin/armv7a-linux-androideabi$TERMUX_PKG_API_LEVEL-clang \
		$TERMUX_STANDALONE_TOOLCHAIN/bin/arm-linux-androideabi-clang
	cp $TERMUX_STANDALONE_TOOLCHAIN/bin/armv7a-linux-androideabi$TERMUX_PKG_API_LEVEL-clang++ \
		$TERMUX_STANDALONE_TOOLCHAIN/bin/arm-linux-androideabi-clang++
	cp $TERMUX_STANDALONE_TOOLCHAIN/bin/armv7a-linux-androideabi-cpp \
		$TERMUX_STANDALONE_TOOLCHAIN/bin/arm-linux-androideabi-cpp

	# rust 1.75.0+ expects this directory to be present
	rm -fr "${TERMUX_STANDALONE_TOOLCHAIN}"/toolchains
	mkdir -p "${TERMUX_STANDALONE_TOOLCHAIN}"/toolchains/llvm/prebuilt
	ln -fs ../../.. "${TERMUX_STANDALONE_TOOLCHAIN}"/toolchains/llvm/prebuilt/linux-x86_64

	# Create a pkg-config wrapper. We use path to host pkg-config to
	# avoid picking up a cross-compiled pkg-config later on.
	local _HOST_PKGCONFIG
	_HOST_PKGCONFIG=$(command -v pkg-config)
	mkdir -p "$PKG_CONFIG_LIBDIR"
	cat > $TERMUX_STANDALONE_TOOLCHAIN/bin/pkg-config <<-HERE
		#!/bin/sh
		export PKG_CONFIG_DIR=
		export PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR
		exec $_HOST_PKGCONFIG "\$@"
	HERE
	chmod +x "$TERMUX_STANDALONE_TOOLCHAIN"/bin/pkg-config

	cd $TERMUX_STANDALONE_TOOLCHAIN/sysroot
	for f in $TERMUX_SCRIPTDIR/ndk-patches/$TERMUX_NDK_VERSION/*.patch; do
		echo "Applying ndk-patch: $(basename $f)"
		sed "s%\@TERMUX_PREFIX\@%${TERMUX_PREFIX}%g" "$f" | \
			sed "s%\@TERMUX_HOME\@%${TERMUX_ANDROID_HOME}%g" | \
			patch --silent -p1;
	done
	# libintl.h: Inline implementation gettext functions.
	# langinfo.h: Inline implementation of nl_langinfo().
	cp "$TERMUX_SCRIPTDIR"/ndk-patches/{libintl.h,langinfo.h} usr/include

	# Remove <sys/capability.h> because it is provided by libcap.
	# Remove <sys/shm.h> from the NDK in favour of that from the libandroid-shmem.
	# Remove <sys/sem.h> as it doesn't work for non-root.
	# Remove <iconv.h> as it's provided by libiconv.
	# Remove <spawn.h> as it's only for future (later than android-27).
	# Remove <zlib.h> and <zconf.h> as we build our own zlib.
	# Remove unicode headers provided by libicu.
	# Remove KHR/khrplatform.h provided by mesa.
	# Remove EGL, GLES, GLES2, and GLES3 provided by mesa.
	# Remove execinfo.h as the backtrace(3) functions it declares are only
	# provided by bionic from API level 33, so packages must not detect
	# them at the default API level.
	# Remove NDK vulkan headers.
	rm usr/include/{sys/{capability,shm,sem},{iconv,spawn,zlib,zconf},KHR/khrplatform,execinfo}.h
	rm usr/include/unicode/{char16ptr,platform,ptypes,putil,stringoptions,ubidi,ubrk,uchar,uconfig,ucpmap,udisplaycontext,uenum,uldnames,ulocdata,uloc,umachine,unorm2,urename,uscript,ustring,utext,utf16,utf8,utf,utf_old,utypes,uvernum,uversion}.h
	rm -Rf usr/include/vulkan
	rm -Rf usr/include/{EGL,GLES{,2,3}}

	# $TERMUX_ELF_CLEANER --api-level=$TERMUX_PKG_API_LEVEL usr/lib/*/*/*.so | { [[ "${CI-}" == "true" ]] && sed -e '1i\::group::Applying `termux-elf-cleaner`' -e '$a\::endgroup::' || cat; }
	for dir in usr/lib/*; do
		# This seem to be needed when building rust
		# packages
		echo 'INPUT(-lunwind)' > $dir/libgcc.a
	done

	grep -lrw $TERMUX_STANDALONE_TOOLCHAIN/sysroot/usr/include/c++/v1 -e 'include <version>' | xargs -n 1 sed -i 's/include <version>/include \"version\"/g'

	touch ${TERMUX_STANDALONE_TOOLCHAIN}/.termux-standalone-toolchain

	termux_patch_ndk_with_gcc_cross
}
