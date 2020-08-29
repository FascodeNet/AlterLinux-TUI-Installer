#
# By Chih-Wei Huang <cwhuang@linux.org.tw>
#
# License: GNU Public License
# We explicitely grant the right to use the scripts
# with Android-x86 project.
#

tempfile=/tmp/temp-$$
menufile=/tmp/menu-$$

CPIO=cpio
OS_TITLE=${OS_TITLE:-Alter-Linux}

rebooting()
{
	dialog --title " Rebooting... " --nocancel --pause "" 8 41 1
	sync
	umount -a
	reboot -f
}

auto_answer()
{
	echo "$answer" > $tempfile
	unset answer
	test "`cat $tempfile`" != "0"
}

set_answer_if_auto()
{
	[ -n "$AUTO_INSTALL" ] && answer="$1"
}

adialog()
{
	if [ -n "$answer" ]; then
		auto_answer
	else
		dialog "$@" 2> $tempfile
	fi
}

choose()
{
	adialog --clear --title " $1 " --menu "$2" 21 79 13 --file $menufile

	retval=$?
	choice=`cat $tempfile`
}

size_gb()
{
	printf %0.2fGB $(dc `cat $1/size` 2097152 / p)
}

find_partition()
{
	grep -H ^$2$ /sys/block/$1/*/partition 2> /dev/null | cut -d/ -f5
}

list_disks()
{
	for b in /sys/block/[shv]d[a-z] /sys/block/mmcblk? /sys/block/nvme*; do
		[ -d $b ] && echo $b
	done
}

auto_partition()
{
	[ "$AUTO_INSTALL" = "force" ] || dialog --title " Auto Installer " --defaultno --yesno \
		"\nYou have chosen the AUTO installation.\n\nThe installer will erase the whole /dev/$1 and install $OS_TITLE to it.\n\nThis is the last confirmation. Are you sure to do so?" 12 61
	[ $? -ne 0 ] && rebooting

	if [ -z "$efi" ]; then
		echo -e "o\nn\np\n1\n\n\nw\n" | fdisk /dev/$1
		p=1
	else
		sgdisk --zap-all /dev/$1
		sgdisk --new=1::+260M --typecode=1:EF00 --largest-new=2 --typecode=2:8300 /dev/$1
		p=2
	fi > /dev/tty6

	while sleep 1; do
		answer=`find_partition $1 $p`
		[ -n "$answer" ] && break
	done
	[ -n "$efi" ] && mkdosfs -n EFI /dev/`find_partition $1 1`
}

partition_drive()
{
	echo -n > $menufile
	for i in `list_disks`; do
		echo -n `basename $i` >> $menufile
		if [ -f $i/removable -a `cat $i/removable` -eq 0 ]; then
			echo -n ' "Harddisk ' >> $menufile
		else
			echo -n ' "Removable' >> $menufile
		fi
		if [ -f $i/size ]; then
			sz=$(size_gb $i)
			[ "$sz" = "0.00GB" ] && sz="<0.01GB"
			printf " %10s" $sz >> $menufile
		fi
		for f in $i/device/model $i/*/name; do
			[ -e $f ] && echo -n " `sed $'s/\x04//g' $f`" >> $menufile && break
		done
		[ "`basename $i`" = "$booted_from" -o -d $i/$booted_from ] && echo -n " *" >> $menufile
		echo '"' >> $menufile
	done
	count=`wc -l < $menufile`
	if [ $count -eq 0 ]; then
		dialog --title " Error " --msgbox \
			"\nOK. There is no hard drive to edit partitions." 8 49
		return 255
	fi

	if [ $count -eq 1 -o "$AUTO_INSTALL" = "force" ]; then
		drive=1
	else
		drive=`basename $AUTO_INSTALL`
	fi
	choice=`awk -v n=$drive '{ if (n == NR || n == $1) print $1 }' $menufile`
	if [ -b /dev/$choice ]; then
		retval=0
	else
		choose "Choose Drive" "Please select a drive to edit partitions:\n\n* - Installer source"
	fi
	if [ $retval -eq 0 ]; then
		if [ -n "$AUTO_INSTALL" ]; then
			auto_partition $choice
			return 1
		fi
		if fdisk -l /dev/$choice | grep -q GPT; then
			part_tool=cgdisk
		elif fdisk -l /dev/$choice | grep -q doesn.t; then
			dialog --title " Confirm " --defaultno --yesno "\n Do you want to use GPT?" 7 29
			[ $? -eq 0 ] && part_tool=cgdisk || part_tool=cfdisk
		else
			part_tool=cfdisk
		fi
		$part_tool /dev/$choice
		if [ $? -eq 0 ]; then
			retval=1
		else
			retval=255
		fi
	fi
	return $retval
}

select_dev()
{
	blkid | grep -v -E "^/dev/block/|^/dev/loop" | cut -b6- | sort | awk '{
		l=""
		t="unknown"
		sub(/:/, "", $1)
		for (i = NF; i > 1; --i)
			if (match($i, "^TYPE")) {
				t=$i
				gsub(/TYPE=|"/, "", t)
			} else if (match($i, "^LABEL")) {
				l=$i
				gsub(/LABEL=|"/, "", l)
			}
		printf("%-11s%-12s%-18s\n", $1, t, l)
	}' > $tempfile

	for d in `ls /sys/block`; do
		for i in /sys/block/$d/$d*; do
			[ -d $i ] || continue
			echo $i | grep -qE "loop|ram|sr|boot|rpmb" && continue
			f=$(grep "`basename $i`" $tempfile || printf "%-11s%-30s" `basename $i` unknown)
			sz=$(size_gb $i)
			[ "$sz" = "0.00GB" ] || printf "$f%10s\n" $sz
		done
	done | awk -v b=$booted_from '{
		if (!match($1, b)) {
			printf("\"%s\" \"", $0)
			system("cd /sys/block/*/"$1"; for f in ../device/model ../device/name; do [ -e $f ] && printf %-17s \"`cat $f`\" && break; done")
			printf("\"\n")
		}
	} END {
		printf("\"\" \"\"\n\"Create/Modify partitions\" \"\"\n\"Detect devices\" \"\"")
	}' > $menufile
	choose "Choose Partition" "Please select a partition to install $OS_TITLE:\n\nRecommended minimum free space - 4GB  |  Optimum free space >= 8GB\n\nPartition | Filesystem | Label            | Size     | Drive name/model"
	return $retval
}

progress_bar()
{
	dialog --clear --title " $1 " --gauge "\n $2" 8 70
}

convert_fs()
{
	if blkid /dev/$1 | grep -q ext2; then
		/system/bin/tune2fs -j /dev/$1
		e2fsck -fy /dev/$1
	fi
	if blkid /dev/$1 | grep -q ext3; then
		/system/bin/tune2fs -O extents,uninit_bg /dev/$1
		e2fsck -fy /dev/$1
	fi
}

format_fs()
{
	local cmd
	echo -e '"Do not re-format" ""\next4 ""\nntfs ""\nfat32 ""' > $menufile
	set_answer_if_auto $FORCE_FORMAT
	choose "Choose filesystem" "Please select a filesystem to format $1:"
	case "$choice" in
		ext4)
			cmd="mkfs.ext3 -L"
			;;
		ntfs)
			cmd="mkntfs -fL"
			;;
		fat32)
			cmd="mkdosfs -n"
			;;
		*)
			;;
	esac
	if [ -n "$cmd" ]; then
		[ -n "$AUTO_INSTALL" ] || dialog --title " Confirm " --defaultno --yesno \
			"\n You chose to format $1 to $choice.\n All data in that partition will be LOST.\n\n Are you sure to format the partition $1?" 10 59
		[ $? -ne 0 ] && return 1
		$cmd Android-x86 /dev/$1 | awk '{
			# FIXME: very imprecise progress
			if (match($0, "done"))
				printf("%d\n", i+=33)
		}' | progress_bar "Formatting" "Formatting partition $1..."
		convert_fs $1
	elif blkid /dev/$1 | grep -q ext[23]; then
		dialog --clear --title " Warning " --yesno \
			"\nYou chose to install android-x86 to an ext2/3 filesystem. We suggest you convert it to ext4 for better reliability and performance." 9 62
		[ $? -eq 0 ] && convert_fs $1
	fi
}

create_entry()
{
	title=$1
	shift
	echo -e "title $title\n\tkernel /$asrc/kernel$vga $@ SRC=/$asrc\n\tinitrd /$asrc/initrd.img\n" >> $menulst
}

create_menulst()
{
	menulst=/hd/grub/menu.lst
	[ -n "$VESA" ] && vga=" vga=788 modeset=0"
	echo -e "${GRUB_OPTIONS:-default=0\ntimeout=6\nsplashimage=/grub/android-x86.xpm.gz\n}root (hd0,$1)\n" > $menulst

	create_entry "$OS_TITLE $VER" quiet $cmdline
	create_entry "$OS_TITLE $VER (Debug mode)" $cmdline DEBUG=2
	create_entry "$OS_TITLE $VER (Debug mode) gralloc.gbm" $cmdline DEBUG=2 GRALLOC=gbm
	create_entry "$OS_TITLE $VER (Debug mode) drmfb-composer gralloc.gbm" $cmdline DEBUG=2 HWC=drmfb GRALLOC=gbm
	create_entry "$OS_TITLE $VER (Debug mode) hwcomposer.drm gralloc.gbm" $cmdline DEBUG=2 HWC=drm GRALLOC=gbm
	create_entry "$OS_TITLE $VER (Debug mode) gralloc.minigbm" DEBUG=2 GRALLOC=minigbm
	create_entry "$OS_TITLE $VER (Debug mode) hwcomposer.drm_minigbm gralloc.minigbm" DEBUG=2 HWC=drm_minigbm GRALLOC=minigbm
	create_entry "$OS_TITLE $VER (Debug mode) hwcomposer.intel gralloc.intel" DEBUG=2 HWC=intel GRALLOC=intel
	create_entry "$OS_TITLE $VER (Debug nomodeset)" nomodeset $cmdline DEBUG=2
	create_entry "$OS_TITLE $VER (Debug video=LVDS-1:d)" video=LVDS-1:d $cmdline DEBUG=2
}

create_winitem()
{
	win=`fdisk -l /dev/$(echo $1 | cut -b-3) | grep ^/dev | cut -b6-12,55- | awk '{
		if (match($2, "NTFS"))
			print $1
	}' | head -1`
	if [ -n "$win" ]; then
		dialog --title " Confirm " --yesno \
			"\nThe installer found a Windows partition in /dev/$win.\n\nDo you want to create a boot item for Windows?" 9 59
		[ $? -ne 0 ] && return 1
		wp=$((`echo $win | cut -b4-`-1))
		echo -e "title Windows\n\trootnoverify (hd$d,$wp)\n\tchainloader +1\n" >> $menulst
	fi
}

check_data_img()
{
	losetup /dev/loop7 data.img
	if blkid /dev/loop7 | grep -q ext[23]; then
		dialog --clear --title " Warning " --yesno \
			"\nYour data.img is an ext2/3 filesystem. We suggest you convert it to ext4 for better reliability." 8 58
		[ $? -eq 0 ] && convert_fs loop7
	fi
	losetup -d /dev/loop7
}

gen_img()
{
	if [ "$fs" = "vfat" ]; then
		( dd bs=1M count=$1 if=/dev/zero | pv -ns $1m | dd of=$2 ) 2>&1 \
			| progress_bar "Creating `basename $2`" "Expect to write $1 MB..."
	else
		dd if=/dev/zero bs=1 count=0 seek=$1M of=$2
	fi
}

create_img()
{
	bname=`basename $2`
	if [ -e $2 ]; then
		dialog --title " Confirm " --defaultno --yesno \
			"\n $bname exists. Overwrite it?" 7 38
		[ $? -ne 0 ] && return 255
		rm -f $2
	fi
	dialog --title " Question " --nook --nocancel --inputbox \
		"\nPlease input the size of the $bname in MB:" 8 63 $1 2> $tempfile
	size=`cat $tempfile`
	[ 0$size -le 0 ] && size=2048
	gen_img $size $2
}

create_data_img()
{
	dialog --title " Confirm " --yesno \
		"\nThe installer is going to create a disk image to save the user data. At least 2048MB free disk space is recommended.\n\nAre you sure to create the image?" 11 62

	if [ $? -eq 0 ]; then
		if create_img 2048 data.img; then
			losetup /dev/loop6 data.img
			mkfs.ext4 -L /data /dev/loop6 > /dev/tty6
		fi
		[ $? -ne 0 ] && dialog --msgbox "\n Failed to create data.img." 7 33
	else
		dialog --title " Warning " --msgbox \
			"\nOK. So data will be save to a RAMDISK(tmpfs), and lose after power off." 8 49
	fi
}

try_upgrade()
{
	[ -d $1 ] && return

	for d in hd/*; do
		[ -e "$d"/ramdisk.img -a -n "`ls "$d"/system* 2> /dev/null`" ] && echo \"`basename $d`\" \"\"
	done | sort -r > $menufile

	count=`wc -l < $menufile`
	if [ $count -gt 1 ]; then
		echo -e '"" ""\n"Install to new folder '`basename $1`'" ""' >> $menufile
		choose "Multiple older versions are found" "Please select one to upgrade:"
	elif [ $count -eq 1 ]; then
		eval choice=`awk '{ print $1 }' $menufile`
		set_answer_if_auto 1
		adialog --title " Question " --yesno \
			"\nAn older version $choice is detected.\nWould you like to upgrade it?" 8 61
		[ $? -eq 0 ] || choice=
	fi

	if [ -n "$choice" ]; then
		prev=hd/$choice
		if [ -d "$prev" ]; then
			mv $prev $1
			for d in `find hd -type l -maxdepth 1`; do
				[ "`readlink $d`" = "$choice" ] && ln -sf `basename $1` $d
			done
			rm -rf $1/data/dalvik-cache/* $1/data/system/wpa_supplicant
			[ -s $1/data/misc/wifi/wpa_supplicant.conf ] && sed -i 's/\(ctrl_interface=\)\(.*\)/\1wlan0/' $1/data/misc/wifi/wpa_supplicant.conf
		fi
	fi
}

get_part_info()
{
	d=0
	while [ 1 ]; do
		h=`echo $d | awk '{ printf("%c", $1+97) }'`
		for part in /sys/block/[shv]d$h/$1 /sys/block/mmcblk$d/$1 /sys/block/nvme0n$(($d+1))/$1; do
			[ -d $part ] && break 2
		done
		d=$(($d+1))
	done
	p=`cat $part/partition`
	disk=$(basename `dirname $part`)
}

wait_for_device()
{
	local t=`echo /sys/block/*/$1/partition`
	[ -f "$t" ] || return 1
	until [ -b /dev/$1 ]; do
		echo add > `dirname $t`/uevent
		sleep 1
	done
}

install_to()
{
	wait_for_device $1 || return 1
	cd /
	mountpoint -q /hd && umount /hd
	[ -n "$AUTO_UPDATE" ] && FORCE_FORMAT=no || FORCE_FORMAT=ext4
	while [ 1 ]; do
		format_fs $1
		try_mount rw /dev/$1 /hd && break
		dialog --clear --title " Error " --defaultno --yesno \
			"\n Cannot mount /dev/$1\n Do you want to format it?" 8 37
		[ $? -ne 0 ] && return 255
		FORCE_FORMAT=ext4
	done

	fs=`cat /proc/mounts | grep /dev/$1 | awk '{ print $3 }'`
	cmdline=`sed "s|\(initrd.*img\s*\)||; s|quiet\s*||; s|\(vga=\w\+\?\s*\)||; s|\(DPI=\w\+\?\s*\)||; s|\(AUTO_INSTALL=\w\+\?\s*\)||; s|\(INSTALL=\w\+\?\s*\)||; s|\(SRC=\S\+\?\s*\)||; s|\(DEBUG=\w\+\?\s*\)||; s|\(BOOT_IMAGE=\S\+\?\s*\)||; s|\(iso-scan/filename=\S\+\?\s*\)||; s|[[:space:]]*$||" /proc/cmdline`

	[ -n "$INSTALL_PREFIX" ] && asrc=$INSTALL_PREFIX || asrc=android-$VER
	set_answer_if_auto 1
	[ -z "$efi" ] && adialog --title " Confirm " --no-label Skip --defaultno --yesno \
		"\n Do you want to install boot loader GRUB?" 7 47
	if [ $? -eq 0 ]; then
		get_part_info $1
		if fdisk -l /dev/$disk | grep -q GPT; then
			umount /hd
			dialog --title " Warning " --defaultno --yesno \
				"\nFound GPT on /dev/$disk. The legacy GRUB can't be installed to GPT. Do you want to convert it to MBR?\n\nWARNING: This is a dangerous operation. You should backup your data first." 11 63
			[ $? -eq 1 ] && rebooting
			plist=$(sgdisk --print /dev/$disk | awk '/^  / { printf "%s:", $1 }' | sed 's/:$//')
			sgdisk --gpttombr=$plist /dev/$disk > /dev/tty6
			until try_mount rw /dev/$1 /hd; do
				sleep 1
			done
		fi
		cp -af /grub /hd
		p=$(($p-1))
		create_menulst $p
		create_winitem $1 $d
		rm -f /hd/boot/grub/stage1
		echo "(hd$d) /dev/$disk" > /hd/grub/device.map
		echo "setup (hd$d) (hd$d,$p)" | grub --device-map /hd/grub/device.map > /dev/tty5
		[ $? -ne 0 ] && return 255
	fi

	[ -n "$efi" ] && adialog --title " Confirm " --no-label Skip --yesno \
		"\n Do you want to install EFI GRUB2?" 7 39
	if [ $? -eq 0 ]; then
		[ -z "$AUTO_INSTALL" -o -n "$AUTO_UPDATE" ] && for i in `list_disks`; do
			disk=`basename $i`
			esp=`sgdisk --print /dev/$disk 2> /dev/null | grep EF00 | awk '{print $1}'`
			[ -n "$esp" ] && boot=`find_partition $disk $esp` && break
		done
		if [ -z "$esp" ]; then
			get_part_info $1
			boot=$(blkid /dev/$disk* | grep -v $disk: | grep vfat | cut -d: -f1 | head -1)
			[ -z "$boot" ] && boot=`find_partition $disk 1` || boot=`basename $boot`
			esp=`cat /sys/block/$disk/$boot/partition`
		fi
		mkdir -p efi
		mountpoint -q efi && umount efi
		wait_for_device $boot
		until try_mount rw /dev/$boot efi; do
			dialog --title " Confirm " --defaultno --yesno "\n Cannot mount /dev/$boot.\n Do you want to format it?" 8 37
			[ $? -eq 0 ] && mkdosfs -n EFI /dev/$boot
		done
		if [ "$efi" = "32" ]; then
			grubcfg=efi/boot/grub/i386-efi/grub.cfg
			bootefi=bootia32.efi
		else
			grubcfg=efi/boot/grub/x86_64-efi/grub.cfg
			bootefi=BOOTx64.EFI
		fi
		if [ -d efi/efi/boot -a ! -s efi/efi/boot/android.cfg ]; then
			efidir=/efi/Android
		else
			efidir=/efi/boot
			rm -rf efi/efi/Android
		fi
		grub-install --target=x86_64-efi --efi-directory=./efi/ --bootloader-id="Alter Linux"
		#mkdir -p `dirname $grubcfg` efi$efidir
		#cp -af grub2/efi/boot/* efi$efidir
		#sed -i "s|VER|$VER|; s|CMDLINE|$cmdline|; s|OS_TITLE|$OS_TITLE|" efi$efidir/android.cfg
		#[ -s efi/boot/grub/grubenv ] || ( printf %-1024s "# GRUB Environment Block%" | sed 's/k%/k\n/; s/   /###/g' > efi/boot/grub/grubenv )

		#echo -e 'set timeout=5\nset debug_mode="(DEBUG mode)"' > $grubcfg
		# Our grub-efi doesn't support ntfs directly.
		# Copy boot files to ESP so grub-efi could read them
		#if [ "$fs" = "fuseblk" ]; then
	#		cp -f src/kernel src/initrd.img efi$efidir
	#		echo -e "set kdir=$efidir\nset src=SRC=/$asrc" >> $grubcfg
	#	else
	#		echo -e "set kdir=/$asrc" >> $grubcfg
	#	fi
	#	echo -e '\nsource $cmdpath/android.cfg' >> $grubcfg
	#	if [ -d src/boot/grub/theme ]; then
	#		cp -R src/boot/grub/[ft]* efi/boot/grub
	#		find efi/boot/grub -name TRANS.TBL -delete
	#	fi

		# Checking for old EFI entries, removing them and adding new depending on bitness
		#efibootmgr | grep -Eo ".{0,6}Alter Linux" | cut -c1-4 > /tmp/efientries
		#if [ -s /tmp/efientries ]; then
		#	set_answer_if_auto 1
		#	adialog --title " Question " --yesno "\nEFI boot entries for previous Alter Linux installations were found.\n\nDo you wish to delete them?" 10 61
		#	[ $? -eq 0 ] && while read entry; do efibootmgr -Bb "$entry" > /dev/tty4 2>&1; done < /tmp/efientries
		#fi
		#efibootmgr -v -c -d /dev/$disk -p $esp -L "Alter Linux $VER" -l $efidir/$bootefi > /dev/tty4 2>&1
	fi

	#try_upgrade hd/$asrc

	mkdir -p hd/$asrc
	cd hd/$asrc
	cp /mnt/airootfs.sfs .
	unsquashfs airootfs.sfs
	mv squashfs-root/* ../


	dialog --infobox "\n Syncing to disk..." 5 27
	sync
	cd /

	return $result
}

install_hd()
{
	case "$AUTO_INSTALL" in
		[Uu]*)
			answer=${AUTO_UPDATE:-$(blkid | grep -v loop | grep -v iso9660 | sort | grep Android-x86 | cut -d: -f1 | head -1)}
			answer=${answer:-$(blkid | grep -v loop | sort | grep ext4 | cut -d: -f1 | head -1)}
			[ -b "$answer" -o -b /dev/$answer ] && answer=`basename $answer` || answer=
			AUTO_UPDATE=${answer:-$AUTO_UPDATE}
			;;
		*)
			[ -z "$answer" ] && set_answer_if_auto Create
			;;
	esac

	select_dev || rebooting
	retval=1
	case "$choice" in
		Create*)
			partition_drive
			retval=$?
			;;
		Detect*)
			dialog --title " Detecting... " --nocancel --pause "" 8 41 1
			;;
		*)
			install_to $choice
			retval=$?
			;;
	esac
	return $retval
}

do_install()
{
	booted_from=`basename $dev`
	efi=$(cat /sys/firmware/efi/fw_platform_size 2> /dev/null)
	[ -n "$efi" ] && mount -t efivarfs none /sys/firmware/efi/efivars

	until install_hd; do
		if [ $retval -eq 255 ]; then
			dialog --title ' Error! ' --yes-label Retry --no-label Reboot \
				--yesno "\nInstallation failed! Please check if you have enough free disk space to install $OS_TITLE." 8 51
			[ $? -eq 1 ] && rebooting
		fi
	done

	[ -n "$VESA" ] || runit="Run $OS_TITLE"
	dialog --clear --title ' Congratulations! ' \
		--menu "\n $OS_TITLE is installed successfully.\n " 11 51 13 \
		"$runit" "" "Reboot" "" 2> $tempfile
	case "`cat $tempfile`" in
		Run*)
			cd /android
			umount system
			mountpoint -q /sfs && umount /sfs
			if [ -e /hd/$asrc/system.sfs ]; then
				mount -o loop /hd/$asrc/system.sfs /sfs
				mount -o loop /sfs/system.img system
			elif [ -e /hd/$asrc/system.img ]; then
				mount -o loop /hd/$asrc/system.img system
			else
				mount --bind /hd/$asrc/system system
			fi
			if [ -d /hd/$asrc/data ]; then
				mount --bind /hd/$asrc/data data
			elif [ -e /hd/$asrc/data.img ]; then
				mount -o loop /hd/$asrc/data.img data
			fi
			;;
		*)
			rebooting
			;;
	esac
}
do_install