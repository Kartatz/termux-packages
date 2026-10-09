TERMUX_PKG_HOMEPAGE=https://www.fefe.de/gatling/
TERMUX_PKG_DESCRIPTION="A high performance http, ftp and smb server"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=0.16
TERMUX_PKG_REVISION=2
TERMUX_PKG_SRCURL=https://web.archive.org/web/2024id_/http://www.fefe.de/gatling/gatling-$TERMUX_PKG_VERSION.tar.xz
TERMUX_PKG_SHA256=5f96438ee201d7f1f6c2e0849ff273b196bdc7493f29a719ce8ed08c8be6365b
TERMUX_PKG_DEPENDS="libcrypt, libiconv, openssl, zlib"
TERMUX_PKG_BUILD_DEPENDS="libcap, libowfat"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_EXTRA_MAKE_ARGS="
prefix=$TERMUX_PREFIX
MANDIR=$TERMUX_PREFIX/share/man
"

termux_step_pre_configure() {
	# The GNUmakefile probes for an MD5 implementation with CFLAGS-only
	# link tests, so the prefix library directory must be visible there
	# for the -lcrypto probe to succeed.
	CFLAGS+=" $CPPFLAGS -L$TERMUX_PREFIX/lib"

	# The GNUmakefile links $(LDFLAGS) in front of the objects, so keep
	# those libraries from being discarded by --as-needed.
	LDFLAGS="${LDFLAGS/-Wl,--as-needed/}"
	LDFLAGS+=" -lcrypt -lcrypto -liconv"
}
