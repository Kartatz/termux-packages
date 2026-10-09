TERMUX_PKG_HOMEPAGE=http://alpine.x10host.com/
TERMUX_PKG_DESCRIPTION="Fast, easy to use email client"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=2.26
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://fossies.org/linux/misc/alpine-${TERMUX_PKG_VERSION}.tar.xz
TERMUX_PKG_SHA256=c0779c2be6c47d30554854a3e14ef5e36539502b331068851329275898a9baba
TERMUX_PKG_DEPENDS="coreutils, libcrypt, ncurses, openssl, openssl-tool"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--disable-debug
--with-c-client-target=lnx
--without-krb5
--without-ldap
--without-pthread
--without-tcl
--with-system-pinerc=${TERMUX_PREFIX}/etc/pine.conf
--with-passfile=$TERMUX_ANDROID_HOME/.pine-passfile
--with-ssl-dir=$TERMUX_PREFIX
--with-ssl-certs-dir=$TERMUX_PREFIX/etc/ssl/certs
--with-ssl-key-dir=$TERMUX_PREFIX/etc/ssl/private
"
TERMUX_PKG_BUILD_IN_SRC=true

# The bundled c-client cannot cope with parallel makes: its once-only
# environment setup creates the "osdep*" sources that are compiled in
# the same run, so racing jobs see "osdepbas.c not found".
TERMUX_PKG_MAKE_PROCESSES=1

termux_step_pre_configure() {
	export TCC=$CC
	export TRANLIB=$RANLIB
	export SPELLPROG=${TERMUX_PREFIX}/bin/hunspell
	export alpine_SSLVERSION=old
	export TPATH=$PATH

	export LIBS="-lcrypt"

	# To get S_IREAD and friends:
	CPPFLAGS+=" -D__USE_BSD"

	cp $TERMUX_PKG_BUILDER_DIR/pine.conf $TERMUX_PREFIX/etc/pine.conf

	touch $TERMUX_PKG_SRCDIR/imap/lnxok

	# The bundled gettext/libtool macros are too old for automake 1.18:
	# having them (or the system copies aclocal installs over them) under
	# the "m4" include directory sends aclocal into a "too many loops"
	# deadlock. Drop the directory from the search path and let
	# autoreconf regenerate everything from the system copies.
	sed -i 's/AC_CONFIG_MACRO_DIR(\[m4\])/AC_CONFIG_MACRO_DIR([])/' configure.ac
	sed -i 's/^ACLOCAL_AMFLAGS = --install -I m4$/ACLOCAL_AMFLAGS =/' Makefile.am
	rm -f m4/*.m4 aclocal.m4
	autoreconf -fi
}

termux_step_post_configure() {
	cd pith
	$CC_FOR_BUILD help_c_gen.c -o help_c_gen
	$CC_FOR_BUILD help_h_gen.c -o help_h_gen
	touch -d "next hour" help_c_gen help_h_gen
}

termux_step_create_debscripts() {
	echo "#!$TERMUX_PREFIX/bin/sh" >> postinst
	echo "if [ ! -e $TERMUX_ANDROID_HOME/.alpine-smime/.pwd/MasterPassword.crt ] && [ ! -e $HOME/.alpine-smime/.pwd/MasterPassword.key ]; then" >> postinst
	echo "echo 'warning making a passwordless masterpasword file'" >> postinst
	echo "mkdir -p \$HOME/.alpine-smime/public \$HOME/.alpine-smime/.pwd \$HOME/.alpine-smime/private \$HOME/.alpine-smime/ca" >> postinst
	echo "openssl req -x509 -newkey rsa:2048 -keyout \$HOME/.alpine-smime/.pwd/MasterPassword.key -out \$HOME/.alpine-smime/.pwd/MasterPassword.crt -days 10000 -nodes -subj '/C=US/ST=dont/L=use/O=this Name/OU=for/CN=anything.com.termux'" >> postinst
	echo "touch \$HOME/.pine-passfile" >> postinst
	echo "fi" >> postinst
}
