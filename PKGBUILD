# Maintainer: Your Name <you@example.com>
#
# NOTE: change `url` and the `source` line to your repository before pushing
# this to the AUR. Until then, use ./install.sh or `make && sudo make install`.
#
pkgname=mchose-adv
pkgver=1.0.0
pkgrel=1
pkgdesc="Userspace bridge for MCHOSE hall-effect keyboard advanced keys (SOCD/RS/DKS) on Linux"
arch=('x86_64' 'aarch64')
url="https://github.com/CHANGEME/mchose-adv"
license=('MIT')
depends=('glibc')
makedepends=('gcc')
provides=('mchose-adv')
conflicts=()
backup=('etc/udev/rules.d/70-mchose-adv.rules')

source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgname-$pkgver"
    make
}

package() {
    cd "$pkgname-$pkgver"

    install -Dm755 mchose-adv \
        "$pkgdir/usr/bin/mchose-adv"

    # udev rule for hidraw access; systemd user unit is enabled per-user, not
    # globally, so it goes to /usr/lib/systemd/user.
    install -Dm644 packaging/70-mchose-adv.rules \
        "$pkgdir/etc/udev/rules.d/70-mchose-adv.rules"
    install -Dm644 packaging/mchose-adv.service \
        "$pkgdir/usr/lib/systemd/user/mchose-adv.service"

    install -Dm644 LICENSE \
        "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    install -Dm644 README.md \
        "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 docs/PROTOCOL.md \
        "$pkgdir/usr/share/doc/$pkgname/PROTOCOL.md"
}
