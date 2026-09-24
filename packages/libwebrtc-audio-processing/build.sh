TERMUX_PKG_HOMEPAGE=https://www.freedesktop.org/software/pulseaudio/webrtc-audio-processing/
TERMUX_PKG_DESCRIPTION="A library containing the AudioProcessing module from the WebRTC project"
TERMUX_PKG_LICENSE="BSD 3-Clause"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="1.3"
TERMUX_PKG_REVISION=5
TERMUX_PKG_SRCURL="https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing/-/archive/v${TERMUX_PKG_VERSION}/webrtc-audio-processing-v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=b04404884e705464c1a2da0d5036ae0fc02d87ed150faa7da4536c99d6966660
TERMUX_PKG_DEPENDS="libc++, abseil-cpp"

termux_step_pre_configure() {
	LDFLAGS+=" $($CC -print-libgcc-file-name)"
}
