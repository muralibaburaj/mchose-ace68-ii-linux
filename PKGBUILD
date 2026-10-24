# Maintainer: muralibaburaj <https://github.com/muralibaburaj>
#
# Arch Linux uses systemd. For Artix, change INIT= in package() to openrc,
# runit, s6 or dinit (or split this into per-init packages).
#
pkgname=mchose-adv-ace68-ii
pkgver=0.2.0
pkgrel=1
pkgdesc="Linux support for MCHOSE Ace68-II advanced keys (SOCD/RS/DKS): HID-BPF fixup rule and userspace bridge"
arch=('x86_64' 'aarch64')
url="https://github.com/muralibaburaj/mchose-ace68-ii-linux"
license=('MIT')
depends=('glibc')
makedepends=('gcc' 'make')
optdepends=('udev-hid-bpf: load the HID-BPF descriptor fixup instead of running the bridge')
backup=('usr/lib/udev/rules.d/70-mchose-ace68-ii.rules')

source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "mchose-ace68-ii-linux-$pkgver"
    make
}

package() {
    cd "mchose-ace68-ii-linux-$pkgver"
    make DESTDIR="$pkgdir" PREFIX=/usr SYSTEMDUNITDIR=/usr/lib/systemd/system \
        INIT=systemd install install-init
}
