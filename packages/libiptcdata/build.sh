TERMUX_PKG_HOMEPAGE=https://libiptcdata.sourceforge.net/
TERMUX_PKG_DESCRIPTION="a C library for manipulating the IPTC metadata stored within multimedia files"
TERMUX_PKG_LICENSE="LGPL-2.0"
TERMUX_PKG_MAINTAINER="Gouranga Das Samrat <gouranga.das.khulna@gmail.com>"
TERMUX_PKG_VERSION="1.0.5"
TERMUX_PKG_SRCURL=https://github.com/ianw/libiptcdata/releases/download/release_${TERMUX_PKG_VERSION//./_}/libiptcdata-${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=c094d0df4595520f194f6f47b13c7652b7ecd67284ac27ab5f219bc3985ea29e

termux_step_make() {
	# The test programs link against the installed library, which is
	# not available when building it for the first time.
	make -C libiptcdata -j $TERMUX_PKG_MAKE_PROCESSES
}
