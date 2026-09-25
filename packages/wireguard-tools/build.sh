TERMUX_PKG_HOMEPAGE=https://www.wireguard.com
TERMUX_PKG_DESCRIPTION="Tools for the WireGuard secure network tunnel"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.0.20210914
TERMUX_PKG_REVISION=3
_COMMIT=3ba6527130c502144e7388b900138bca6260f4e8
TERMUX_PKG_SRCURL=git+https://github.com/wireguard/wireguard-tools
TERMUX_PKG_SHA256=683f1f3e1022237e141379ddaded1af4d7e1475cd16fa175615ae3962c7d0a4e
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_GIT_BRANCH=v1.0.20210914

termux_step_post_get_source() {
	git fetch --unshallow
	git checkout "$_COMMIT"

	local s=$(find . -type f ! -path '*/.git/*' -print0 | xargs -0 sha256sum | LC_ALL=C sort | sha256sum)
	if [[ "${s}" != "${TERMUX_PKG_SHA256}  "* ]]; then
		termux_error_exit "Checksum mismatch for source files."
	fi
}
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_EXTRA_MAKE_ARGS=" -C src WITH_BASHCOMPLETION=yes WITH_WGQUICK=no WITH_SYSTEMDUNITS=no"

termux_step_post_make_install() {
	cd src/wg-quick
	$CC $CFLAGS $LDFLAGS -DWG_CONFIG_SEARCH_PATHS="\"$TERMUX_ANDROID_HOME/.wireguard $TERMUX_PREFIX/etc/wireguard /data/misc/wireguard /data/data/com.wireguard.android/files\"" -o wg-quick android.c
	install -Dm0700 wg-quick $TERMUX_PREFIX/bin/wg-quick
}
