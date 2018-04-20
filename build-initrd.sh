#!/bin/sh

set -e

export FLASH_KERNEL_SKIP=1
export DEBIAN_FRONTEND=noninteractive
DEFAULTMIRROR="https://deb.debian.org/debian"
APT_COMMAND="apt -y"

usage() {
	echo "Usage:

-a|--arch	Architecture to create initrd for. Default armhf
-m|--mirror	Custom mirror URL to use. Must serve your arch.
"
}

echob() {
	echo "Builder: $@"
}

while [ $# -gt 0 ]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	-a | --arch)
		[ -n "$2" ] && ARCH=$2 shift || usage
		;;
	-m | --mirror)
		[ -n "$2" ] && MIRROR=$2 shift || usage
		;;
	esac
	shift
done

# Defaults for all arguments, so they can be set by the environment
[ -z $ARCH ] && ARCH="armhf"
[ -z $MIRROR ] && MIRROR=$DEFAULTMIRROR
[ -z $RELEASE ] && RELEASE="testing"
[ -z $ROOT ] && ROOT=./build/$ARCH
[ -z $OUT ] && OUT=./out
[ -z $VER ] && VER="$ARCH"

# list all packages needed for building the initrd here
[ -z $INCHROOTPKGS ] && INCHROOTPKGS="initramfs-tools"

BOOTSTRAP_BIN="qemu-debootstrap --arch $ARCH --variant=minbase"

umount_chroot() {
	chroot $ROOT umount /sys >/dev/null 2>&1 || true
	chroot $ROOT umount /proc >/dev/null 2>&1 || true
	echo
}

do_chroot() {
	trap umount_chroot INT EXIT
	ROOT="$1"
	CMD="$2"
	echob "Executing \"$2\" in chroot"
	chroot $ROOT mount -t proc proc /proc
	chroot $ROOT mount -t sysfs sys /sys
	chroot $ROOT $CMD
	umount_chroot
	trap - INT EXIT
}

if [ ! -e $ROOT/.min-done ]; then

	[ -d $ROOT ] && rm -r $ROOT

	# create a plain chroot to work in
	echob "Creating chroot with arch $ARCH in $ROOT"
	mkdir build || true
	$BOOTSTRAP_BIN $RELEASE $ROOT $MIRROR || cat $ROOT/debootstrap/debootstrap.log

	sed -i 's,'"$DEFAULTMIRROR"','"$MIRROR"',' $ROOT/etc/apt/sources.list

	# make sure we do not start daemons at install time
	mv $ROOT/sbin/start-stop-daemon $ROOT/sbin/start-stop-daemon.REAL
	echo $START_STOP_DAEMON >$ROOT/sbin/start-stop-daemon
	chmod a+rx $ROOT/sbin/start-stop-daemon

	echo $POLICY_RC_D >$ROOT/usr/sbin/policy-rc.d

	echo "nameserver 8.8.8.8" >$ROOT/etc/resolv.conf
	do_chroot $ROOT "$APT_COMMAND update"

	touch $ROOT/.min-done
else
	echob "Build environment for $ARCH found, reusing."
fi

# install all packages we need to roll the generic initrd
do_chroot $ROOT "$APT_COMMAND update"
do_chroot $ROOT "$APT_COMMAND dist-upgrade"
do_chroot $ROOT "$APT_COMMAND install $INCHROOTPKGS --no-install-recommends"

export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/lib/$DEB_HOST_MULTIARCH"

do_chroot $ROOT "update-initramfs -tc -k generic-$VER -v"

mkdir $OUT >/dev/null 2>&1 || true
cp $ROOT/boot/initrd.img-generic-$VER $OUT
cd $OUT
cd - >/dev/null 2>&1
