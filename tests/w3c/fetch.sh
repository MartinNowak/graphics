#!/usr/bin/env bash
# Fetch and unpack the W3C SVG 1.1 Second Edition test suite (2011-08-16
# release, the final SVG 1.1 archive) into tests/w3c/suite/.
#
# The archive root has no top-level directory: it unpacks svg/, png/,
# harness/, resources/, images/ and svgweb/ directly, hence the -C suite.
# suite/ is gitignored; only the sha256-pinned URL below is committed.
set -euo pipefail
cd "$(dirname "$0")"

URL=https://www.w3.org/Graphics/SVG/Test/20110816/archives/W3C_SVG_11_TestSuite.tar.gz
SHA256=b5f46cca1ad79b670f9179770b2366c57efd5c671d084144090feab4b7ff1030
TARBALL=W3C_SVG_11_TestSuite.tar.gz

if [ ! -f "$TARBALL" ] || ! echo "$SHA256  $TARBALL" | sha256sum --status -c -; then
    curl -fL --retry 3 -o "$TARBALL" "$URL"
fi
echo "$SHA256  $TARBALL" | sha256sum -c -

rm -rf suite
mkdir suite
tar xzf "$TARBALL" -C suite

# The suite ships one gzipped test (conform-viewers-01-t.svgz); unpack it so
# every test is a plain .svg and run.sh only deals with one file form.
# (gunzip refuses the .svgz suffix, hence the explicit -c.)
gunzip -c suite/svg/conform-viewers-01-t.svgz >suite/svg/conform-viewers-01-t.svg
rm suite/svg/conform-viewers-01-t.svgz

echo "$(ls suite/svg/*.svg | wc -l) tests in suite/svg/, $(ls suite/png/*.png | wc -l) reference images in suite/png/"
