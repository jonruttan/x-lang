# digest.sh -- the harness's digests, sourced: `. tools/lib/digest.sh`.
#
# Each takes the tool the host has, the coreutils name first (GNU, busybox,
# x-coreutils), then macOS's shasum, and prints what sha256sum prints: one
# `HASH  NAME` line a file, `HASH  -` for standard input when no FILE is
# named.  Neither tool on PATH is an error naming the one wanted.
#
#   x_sha256 [FILE...]      SHA-256
#   x_sha256_check SUMS     checks SUMS, a sha256sum-format list, quietly
#   x_sha1 [FILE...]        SHA-1, for the keys the image cache already uses
#
# x.sh defines the same three for itself: it is installed alone as bin/x
# and cannot reach this file.

x_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"
	elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"
	else echo "digest: no sha256sum or shasum on PATH" >&2; return 2; fi
}

x_sha256_check() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "$1" >/dev/null 2>&1
	elif command -v shasum >/dev/null 2>&1; then shasum -a 256 -c "$1" >/dev/null 2>&1
	else echo "digest: no sha256sum or shasum on PATH" >&2; return 2; fi
}

x_sha1() {
	if command -v sha1sum >/dev/null 2>&1; then sha1sum "$@"
	elif command -v shasum >/dev/null 2>&1; then shasum -a 1 "$@"
	else echo "digest: no sha1sum or shasum on PATH" >&2; return 2; fi
}
