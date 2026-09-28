TERMUX_PKG_HOMEPAGE=https://github.com/aristocratos/btop
TERMUX_PKG_DESCRIPTION="Resource monitor that shows usage and stats for processor, memory, disks, network and processes."
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@tstein <me@tedstein.net>"
TERMUX_PKG_VERSION="1.4.7"
TERMUX_PKG_REVISION=1
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_SRCURL="https://github.com/aristocratos/btop/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=933de2e4d1b2211a638be463eb6e8616891bfba73aef5d38060bd8319baeefc6
TERMUX_PKG_BUILD_DEPENDS="aosp-libs, lowdown"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
	-DBTOP_LTO=OFF
	-DBTOP_GPU=OFF
"

termux_step_pre_configure() {
	if [[ "$TERMUX_ON_DEVICE_BUILD" == "true" ]]; then
		return
	fi

	# The man page generation runs lowdown through proot with the
	# minimal AOSP environment, whose libc does not provide the symbols
	# used by our builds. Skip it instead of fighting the loader.
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" -DLOWDOWN_EXECUTABLE=LOWDOWN_EXECUTABLE-NOTFOUND"
}
