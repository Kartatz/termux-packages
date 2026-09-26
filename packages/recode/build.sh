# Contributor: @s00se
TERMUX_PKG_HOMEPAGE="https://github.com/pinard/Recode"
TERMUX_PKG_DESCRIPTION="Charset converter tool and library"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="3.7.15"
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://github.com/rrthomas/recode/releases/download/v${TERMUX_PKG_VERSION}/recode-${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=f590407fc51badb351973fc1333ee33111f05ec83a8f954fd8cf0c5e30439806
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="libiconv"
# recode needs to be explicitly linked to avoid:
# CANNOT LINK EXECUTABLE "recode": cannot locate symbol "libiconv_open"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="LIBS=-liconv"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS+="
ac_cv_path_HELP2MAN=:
"

termux_step_pre_configure() {
	# The toolchain resolves its headers before the build directories, so
	# the gnulib stdio.h wrapper providing these macros is never included.
	CPPFLAGS+=" -include $TERMUX_PKG_BUILDER_DIR/gnulib-attrs.h"
}

termux_step_post_configure() {
	make -C lib limits.h >/dev/null
	sed -i 's|# include_next <limits.h>|# include <limits.h>|' lib/limits.h
}
