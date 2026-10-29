#!/bin/sh
# Creates a local, self-signed code signing certificate for Clipt.
#
# Why this exists: an ad-hoc signature (`codesign -s -`) gives the app a
# designated requirement of `cdhash H"..."` -- the hash of that exact binary.
# macOS ties privacy grants (such as Accessibility, needed for auto-paste) to that
# requirement, so every rebuild produces a new identity and the permission silently
# stops applying.
#
# Signing with a certificate instead gives a designated requirement of
# `identifier "com.brentc22.Clipt" and certificate leaf = H"..."`. Both halves
# stay the same across rebuilds, so the grant survives.
#
# The certificate is self-signed and not trusted by the system. That is fine:
# codesign accepts it. It buys a stable identity, not trust.
#
# Usage:
#   scripts/make-signing-cert.sh            create the identity in the login keychain
#   scripts/make-signing-cert.sh --export DIR
#                                           also write DIR/clipt-signing.p12 and print its
#                                           base64, for the GitHub secret CLIPT_SIGNING_P12
#                                           (the password "clipt" goes in CLIPT_SIGNING_PASSWORD)
#
# Safe to re-run: it does not create a second identity. With --export it needs a
# fresh certificate, so exporting only works on the run that creates it.
# To remove it: Keychain Access > login > "Clipt Self-Signed", delete.

set -eu

NAME="Clipt Self-Signed"
PASSWORD="clipt"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
EXPORT_DIR=""

if [ "${1:-}" = "--export" ]; then
    EXPORT_DIR="${2:-}"
    if [ -z "$EXPORT_DIR" ]; then
        echo "usage: $0 [--export <dir>]" >&2
        exit 2
    fi
elif [ $# -gt 0 ]; then
    echo "usage: $0 [--export <dir>]" >&2
    exit 2
fi

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "identity \"$NAME\" already exists -- nothing to do"
    if [ -n "$EXPORT_DIR" ]; then
        echo "--export needs a freshly created identity; delete \"$NAME\" from the keychain and re-run" >&2
        exit 1
    fi
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    >/dev/null 2>"$TMP/openssl.log" || { cat "$TMP/openssl.log" >&2; exit 1; }

# macOS `security` cannot read PKCS#12 files written with OpenSSL 3's default
# algorithms, so ask for the older ones explicitly. Without this the import
# fails with "MAC verification failed during PKCS12 import (wrong password?)",
# which is misleading -- the password is fine.
openssl pkcs12 -export \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" \
    -passout "pass:$PASSWORD" -name "$NAME" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    >/dev/null 2>"$TMP/openssl.log" || { cat "$TMP/openssl.log" >&2; exit 1; }

# Only codesign may use the key without a prompt. Not `-A` (any app): the key is what
# makes a binary count as Clipt for its privacy grants, so a process that could
# sign with it silently could inherit them.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign

echo "created code signing identity \"$NAME\""

if [ -n "$EXPORT_DIR" ]; then
    mkdir -p "$EXPORT_DIR"
    cp "$TMP/cert.p12" "$EXPORT_DIR/clipt-signing.p12"
    echo "wrote $EXPORT_DIR/clipt-signing.p12 (password: $PASSWORD)"
    echo "store this as the GitHub secret CLIPT_SIGNING_P12:"
    base64 -i "$EXPORT_DIR/clipt-signing.p12"
fi

echo "run 'make install' to sign Clipt with it"
