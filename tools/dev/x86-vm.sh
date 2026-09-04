#!/bin/sh
# x86-vm.sh -- a local x86-64 Linux box, on a machine that is neither.
#
# WHY THIS EXISTS.  x-lang's JIT lane (`compile-asm`) has a crash that appears
# only on x86-64 Linux, and the development machines are Apple Silicon.  Every
# cheaper way of reaching that target was tried first and every one of them
# lied:
#
#   Rosetta 2 (x86-64 macOS)   runs the JIT faithfully -- and does NOT
#                              reproduce.  Right ISA, wrong OS.
#   Rosetta for Linux          dies on an unimplemented syscall (338).
#   qemu-user / docker amd64   crashes the KNOWN-GOOD configuration too, so
#                              a crash there proves nothing.
#   VirtualBox                 cannot run an x86-64 guest on an arm64 host.
#
# What is left is full-system emulation: qemu-system-x86_64 emulates the whole
# machine, including the MMU, so freshly-mmap'd executable pages are
# invalidated and re-translated the way real hardware would.  That is the
# property qemu-user lacked, and it is the reason this file is a VM and not a
# one-line docker invocation.
#
# It is SLOW -- TCG on this host is roughly an order of magnitude off native,
# so a full tower boot is minutes, not seconds.  That is the price of the only
# faithful local x86-64 Linux available.  The remote server stays the fast
# path for full suite runs; this is the one that works offline, that can be
# rebuilt from scratch, and that anyone with a checkout can bring up.
#
#   sh tools/dev/x86-vm.sh up            # boot (first run provisions; ~5 min)
#   sh tools/dev/x86-vm.sh run 'make -s' # sync the tree in and run a command
#   sh tools/dev/x86-vm.sh ssh           # interactive shell
#   sh tools/dev/x86-vm.sh down          # graceful shutdown
#   sh tools/dev/x86-vm.sh destroy       # forget the disk, keep the download
#
# Everything mutable lives outside the checkout, under ~/.cache/x-lang/x86-vm,
# so `destroy` can never take a source tree with it.
#
# A SECOND REASON TO WANT ONE.  The allocation ceiling is not an OOM guard --
# the runners default to a limit far past physical memory, and a runaway engine
# has taken this workstation down more than once.  Inside the guest that same
# runaway hits a 4G wall, the guest's own OOM killer reaps it, and the host
# never notices.  Chasing a crash in the allocator is exactly the work where
# that matters.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# The tree to send over.  Defaults to the checkout this script sits in, but a
# worktree-per-branch layout means the code under test is often NOT that one.
SRC_DIR="${X86_VM_SRC:-$PROJECT_DIR}"

VM_DIR="${X86_VM_DIR:-$HOME/.cache/x-lang/x86-vm}"
# 8G, NOT A ROUND-NUMBER GUESS.  A cold tower boot -- `x.sh -l xe` on an empty
# JIT cache -- peaks at 2.4G on arm64 and rather more here, and a 4G guest was
# OOM-killed doing nothing more exotic than `(display 1)`.  qemu allocates
# guest memory lazily, so the ceiling costs nothing until the guest touches it.
MEM="${X86_VM_MEM:-8192}"
CPUS="${X86_VM_CPUS:-2}"
PORT="${X86_VM_PORT:-2222}"
CPU_MODEL="${X86_VM_CPU:-max}"
DISK_SIZE="${X86_VM_DISK:-20G}"

# Debian's genericcloud image: no installer, no desktop, boots on SeaBIOS with
# virtio, and takes its whole configuration from a cloud-init seed.  Pinned to
# bookworm because the bug is being chased on Ubuntu 22.04-era glibc/gcc, and
# a moving `latest` would make two runs a month apart incomparable.
IMG_URL="${X86_VM_IMG_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2}"

BASE="$VM_DIR/base.qcow2"
DISK="$VM_DIR/disk.qcow2"
SEED="$VM_DIR/seed.iso"
PIDFILE="$VM_DIR/vm.pid"
CONSOLE="$VM_DIR/console.log"
KEY="$VM_DIR/id_ed25519"
GUEST_DIR=/home/x/x-lang

QEMU=qemu-system-x86_64

die() { printf 'x86-vm: %s\n' "$*" >&2; exit 1; }
say() { printf 'x86-vm: %s\n' "$*"; }

# Deliberately unquoted at every use site: this is an argument LIST, and
# quoting it hands ssh one nonsense argument.  Hence the SC2086 waivers below.
SSH_OPTS="-i $KEY -p $PORT \
	-o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null \
	-o LogLevel=ERROR \
	-o ConnectTimeout=5"

vm_pid() { [ -s "$PIDFILE" ] && cat "$PIDFILE"; }

vm_running() {
	pid=$(vm_pid) || return 1
	[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# ---------------------------------------------------------------- provisioning

fetch_base() {
	[ -s "$BASE" ] && return 0
	command -v curl >/dev/null || die "curl not found"
	say "downloading the base image (~320M, once)"
	curl -fL --retry 3 -o "$BASE.part" "$IMG_URL"
	mv "$BASE.part" "$BASE"
}

make_key() {
	[ -s "$KEY" ] && return 0
	# A key of its own, not the operator's: this one is passphraseless by
	# design and only ever authorises a throwaway local guest.
	ssh-keygen -q -t ed25519 -N '' -C x-lang-x86-vm -f "$KEY"
}

make_seed() {
	[ -s "$SEED" ] && return 0
	seeddir="$VM_DIR/seed"
	rm -rf "$seeddir"
	mkdir -p "$seeddir"

	cat > "$seeddir/meta-data" <<-EOF
	instance-id: x-lang-x86
	local-hostname: x-lang-x86
	EOF

	{
		cat <<-EOF
		#cloud-config
		users:
		  - name: x
		    sudo: 'ALL=(ALL) NOPASSWD:ALL'
		    shell: /bin/bash
		    ssh_authorized_keys:
		      - $(cat "$KEY.pub")
		package_update: true
		# Swap as well as RAM: the failure being chased lives in the
		# allocator, and the difference between "swapped and slow" and
		# "OOM-killed at rc=137" is the difference between a run that
		# tells you something and one that does not.
		swap:
		  filename: /swapfile
		  size: 4294967296
		  maxsize: 4294967296
		packages:
		EOF
		# What a checkout needs to build the engine and run the suite.
		for p in build-essential git curl rsync file gdb time bzip2 xz-utils; do
			printf '  - %s\n' "$p"
		done
	} > "$seeddir/user-data"

	# No cloud-localds and no mkisofs on a stock Mac; hdiutil is built in and
	# makes an ISO9660 whose volume name is what NoCloud looks for.
	if command -v cloud-localds >/dev/null; then
		cloud-localds "$SEED" "$seeddir/user-data" "$seeddir/meta-data"
	elif command -v hdiutil >/dev/null; then
		hdiutil makehybrid -quiet -o "$SEED" -iso -joliet \
			-default-volume-name cidata "$seeddir"
	else
		die "need cloud-localds or hdiutil to build the cloud-init seed"
	fi
}

make_disk() {
	[ -s "$DISK" ] && return 0
	say "creating a $DISK_SIZE overlay on the base image"
	qemu-img create -q -f qcow2 -F qcow2 -b "$BASE" "$DISK" "$DISK_SIZE"
}

# -------------------------------------------------------------------- commands

cmd_up() {
	if vm_running; then say "already up on port $PORT"; return 0; fi
	command -v "$QEMU" >/dev/null || die "$QEMU not found (brew install qemu)"
	mkdir -p "$VM_DIR"
	fetch_base
	make_key
	make_seed
	make_disk

	# ds=nocloud VIA SMBIOS, NOT JUST THE SEED.  A correct seed is not enough:
	# cloud-init's generator runs ds-identify first, and when that probe comes
	# up empty it DISABLES cloud-init outright -- no user, no host keys, and
	# an ssh.service that fails to start, which reads like a networking fault
	# and is not one.  Naming the datasource on the SMBIOS serial takes the
	# guess out of it, and is inert on a guest that had found the seed anyway.
	say "booting (tcg, ${CPUS}x, ${MEM}M) -- console: $CONSOLE"
	rm -f "$PIDFILE"
	"$QEMU" \
		-machine q35 -cpu "$CPU_MODEL" -smp "$CPUS" -m "$MEM" \
		-drive if=virtio,format=qcow2,file="$DISK" \
		-drive if=virtio,format=raw,file="$SEED",media=cdrom,readonly=on \
		-smbios type=1,serial=ds=nocloud \
		-netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22" \
		-device virtio-net-pci,netdev=n0 \
		-display none -serial "file:$CONSOLE" -monitor none \
		-daemonize -pidfile "$PIDFILE"

	# First boot runs cloud-init (user creation, apt) under emulation, which
	# is the slow part; later boots answer in well under a minute.
	say "waiting for ssh (first boot provisions; be patient)"
	i=0
	while [ "$i" -lt 180 ]; do
		# shellcheck disable=SC2086
		if ssh $SSH_OPTS x@127.0.0.1 true 2>/dev/null; then
			# SSH ANSWERS BEFORE THE BOX IS USABLE.  cloud-init brings
			# sshd up early and installs the compiler late, so the
			# first `up` used to hand back a guest with no gcc -- and
			# the resulting "gcc: command not found" reads like a
			# broken image rather than a race.  Wait for the real end.
			say "ssh is up; waiting for provisioning to finish"
			cmd_ssh 'cloud-init status --wait >/dev/null 2>&1 || true'
			say "up: sh tools/dev/x86-vm.sh ssh"
			# Expands in the guest, not here.
			# shellcheck disable=SC2016
			cmd_ssh 'uname -m; . /etc/os-release; echo "$PRETTY_NAME"; cc --version | head -1'
			return 0
		fi
		vm_running || die "qemu exited -- see $CONSOLE"
		i=$((i + 5))
		sleep 5
	done
	die "no ssh after 15 minutes -- see $CONSOLE"
}

cmd_ssh() {
	vm_running || die "not running (sh tools/dev/x86-vm.sh up)"
	if [ $# -eq 0 ]; then
		# shellcheck disable=SC2086
		ssh $SSH_OPTS x@127.0.0.1
	else
		# The command is composed HERE and expands in the guest's shell,
		# which is what a caller passing `make -s test-x` wants.
		# shellcheck disable=SC2086,SC2029
		ssh $SSH_OPTS x@127.0.0.1 "$@"
	fi
}

# The tree goes over as FILES, without .git.  This is a worktree checkout as
# often as not, where .git is a pointer file into another directory and copying
# it yields a repository that is broken in a confusing way.  Everything the
# guest is here to do -- build the engine, run x.sh, run the spec suite -- works
# without history; the gates that shell out to git do not, and want a clone.
cmd_sync() {
	vm_running || die "not running (sh tools/dev/x86-vm.sh up)"
	command -v rsync >/dev/null || die "rsync not found"
	say "syncing $SRC_DIR -> $GUEST_DIR"
	rsync -a --delete \
		--exclude '.git' \
		--exclude 'deps/' \
		--exclude 'docs/ref/' \
		--exclude 'x-bin*' \
		--exclude '*.o' \
		-e "ssh $SSH_OPTS" \
		"$SRC_DIR/" "x@127.0.0.1:$GUEST_DIR/"
}

cmd_run() {
	[ $# -gt 0 ] || die "run: needs a command"
	cmd_sync
	cmd_ssh "cd $GUEST_DIR && $*"
}

cmd_down() {
	vm_running || { say "not running"; return 0; }
	say "shutting down"
	cmd_ssh 'sudo poweroff' 2>/dev/null || true
	i=0
	while vm_running && [ "$i" -lt 60 ]; do i=$((i + 2)); sleep 2; done
	if vm_running; then
		say "still up after 60s -- killing $(vm_pid)"
		kill "$(vm_pid)" 2>/dev/null || true
	fi
	rm -f "$PIDFILE"
}

cmd_destroy() {
	cmd_down
	# The base image and the key survive: re-provisioning is cheap, the
	# 320M download is not.
	rm -f "$DISK" "$SEED"
	rm -rf "$VM_DIR/seed"
	say "disk and seed removed; base image kept at $BASE"
}

cmd_status() {
	if vm_running; then
		say "running (pid $(vm_pid), ssh port $PORT)"
	else
		say "not running"
	fi
	[ -s "$BASE" ] && say "base image: $(du -h "$BASE" | cut -f1)"
	[ -s "$DISK" ] && say "disk:       $(du -h "$DISK" | cut -f1)"
	return 0
}

usage() {
	cat <<-EOF
	usage: sh tools/dev/x86-vm.sh <command>

	  up             boot the VM, provisioning it on first run
	  ssh [cmd...]   run a command in the guest, or open a shell
	  sync           copy this checkout into the guest
	  run <cmd...>   sync, then run a command in the guest's checkout
	  status         is it up, and how big is it
	  down           graceful shutdown
	  destroy        down, then remove the disk (keeps the download)

	environment: X86_VM_SRC ($SRC_DIR)
	             X86_VM_MEM ($MEM) X86_VM_CPUS ($CPUS) X86_VM_PORT ($PORT)
	             X86_VM_CPU ($CPU_MODEL) X86_VM_DISK ($DISK_SIZE)
	             X86_VM_DIR ($VM_DIR)
	EOF
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
	up)      cmd_up ;;
	ssh)     cmd_ssh "$@" ;;
	sync)    cmd_sync ;;
	run)     cmd_run "$@" ;;
	status)  cmd_status ;;
	down)    cmd_down ;;
	destroy) cmd_destroy ;;
	""|-h|--help|help) usage ;;
	*)       usage >&2; exit 1 ;;
esac
