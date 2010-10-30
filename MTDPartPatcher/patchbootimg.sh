#!/sbin/sh
# patchbootimg.sh 
# 2010-06-24 Firerat
# patch boot.img with custom partition table
# Credits lbcoder
# http://forum.xda-developers.com/showthread.php?t=704560
# 2010-07-06 Firerat, added androidboot.bootloader=1.33.2005
# 2010-08-05 Firerat, ROM Manger compatible cache
# 2010-08-05 Firerat, legacy /system/sd support in cache bind mount
# 2010-08-05 Firerat, get partition table from dmesg
# 2010-08-06 Firerat, consolidated recovery and boot script into one ( makes life much easier )
# 2010-08-13 Firerat, reverted the 0x0.. strip, fixed typo in cmdline creation 
# 2010-08-13 Firerat, added 'All in One' script launcher
# 2010-08-13 Firerat, comment out 'fallback for dream/sapphire"
# 2010-08-15 Firerat, added a 'test' mode, so I can get the cmdline from a devices dmesg
# 2010-10-24 Firerat, get the end of userdata partition ( so we can work out its size )
# 2010-10-27 Firerat, bumped version to 1.5.6
# 2010-10-27 Firerat, added an init.rc patcher, to fix broken roms that don't run boot scripts
# 2010-10-27 Firerat, stripped out the test mode, it was bugging me, will add better one TODO
# 2010-10-27 Firerat, boot mode now gets the full cmdline from /proc/cmdline.. much cleaner
# 2010-10-27 Firerat, added cache to sanity check
# 2010-10-28 Firerat, added a remove feature ( to return to stock SPL MTD partitions )
# 2010-10-30 Firerat, get every partition from dmesg, better device compatibility, e.g. Evo4g has wimax partition 
# 2010-10-30 Firerat, thinking of bumping up to v2.0.0, then use tags for versions and branches from device specific 'fixes' ( if any )


###############################################################################################

###############################################################################################


version=1.5.6
##

readdmesg ()
{
$dmesg|awk '/0x.+: "/ {sub(/-/," ");gsub(/"/,"");gsub(/0x/,"");printf $6" 0x"toupper ($3)" 0x"toupper ($4)"\n"}' > $dmesgmtdpart

# need a sanity check, what if recovery had been running for ages and the dmesg buffer had been filled?
for sanity in misc recovery boot system cache userdata;do
    if [ `grep -q $sanity $dmesgmtdpart;echo $?` = "0" ];
    then
        sain=y
    else
        sain=n
        break
    fi
done
if [ "$sain" = "y" ];
then
	CLInit="mtdparts=msm_nand:"
    for partition in `cat $dmesgmtdpart|awk '!/system|cache|userdata/ {print $1}'`;do
        eval ${partition}StartHex=`awk '/'$partition'/ {print $2}' $dmesgmtdpart`
        eval ${partition}EndHex=`awk '/'$partition'/ {print $3}' $dmesgmtdpart`
    done
    for partition in `cat $dmesgmtdpart|awk '!/system|cache|userdata/ {print $1}'`;do
        eval StartHex=\$${partition}StartHex
        eval EndHex=\$${partition}EndHex
        eval ${partition}SizeKBytes=`expr \( $(printf %d $EndHex) - $(printf %d $StartHex) \) \/ 1024 `
        eval SizeKBytes=\$${partition}SizeKBytes
		CLInit="${CLInit}`echo \"${SizeKBytes}K@${StartHex}\(${partition}\)\"`,"
    done
	CLInit="`echo $CLInit|sed s/,\$//`"
else
    echo -e "${boot} Patcher v${version}\npartition layout not found in dmesg\nand Dream/Magic not found\nPlease use ${boot} patcher early" >> $logfile
    exit
fi
return
}

recoverymode ()
{
if [ ! -e $mapfile ];
then
	echo "${boot} Patcher v${version}\n$mapfile does not exist, please create it with system and cache size, e.g. echo \"mtd 115 2\" \> $mapfile" >> $logfile
	exit
else
	busybox dos2unix $mapfile
	systemMB=`awk '/mtd/ {print $2}' $mapfile`
	cacheMB=`awk '/mtd/ {print $3}' $mapfile`
	FakeSPL=`awk '/spl/ {print $2}' $mapfile`
	
	if [ "$cacheMB" -lt "2" -o "$cacheMB" = "" ];
	then
	# need at least 2mb cache for recovery to not complain
		cacheMB=2
	fi
		
	if [ "$systemMB" = "" ];
	then
		echo "${boot} Patcher v${version}\nPlease configure system size\n with in $mapfile\n e.g. echo \"mtd 115 2\" \> $mapfile" >> $logfile
		exit
	fi

	if [ "$FakeSPL" = "" ];
	then
		CLInit="$CLInit"
	else
		CLInit="androidboot.bootloader=$FakeSPL $CLInit"
	fi
fi
return
}

CreateCMDline ()
{
systemStartHex=`awk '/system/ { print $2 }' $dmesgmtdpart`
systemStartBytes=`printf %d $(awk '/system/ { print $2 }' $dmesgmtdpart)`
systemSizeKBytes=`expr $systemMB \* 1024`
systemBytes=`expr $systemSizeKBytes \* 1024`

cacheSizeKBytes=`expr $cacheMB \* 1024`
cacheBytes=`expr $cacheSizeKBytes \* 1024`
cacheStartBytes=`expr $systemStartBytes + $systemBytes`
cacheStartHex=`printf '%X' $cacheStartBytes`

DataStartBytes=`expr $cacheStartBytes + $cacheBytes`
DataStartHex=`printf '%X' ${DataStartBytes}`
DataBytes=`expr $(printf '%d' ${userdataEndHex}) - $DataStartBytes`
DataKBytes=`expr ${DataBytes} \/ 1024`

KCMDline="${CLInit},${systemSizeKBytes}k@${systemStartHex}(system),${cacheSizeKBytes}k@0x${cacheStartHex}(cache),${DataKBytes}k@0x${DataStartHex}(userdata)"
return
}

GetCMDline ()
{
KCMDline="mtdparts`cat /proc/cmdline|awk -Fmtdparts '{print $2}'`"
if [ "$KCMDline" = "mtdparts" ];
then
	KCMDline=""
fi
return
}

dumpimg ()
{
dump_image ${boot} $wkdir/${boot}.img
$wkdir/unpackbootimg $wkdir/${boot}.img $wkdir/
rm $wkdir/${boot}.img
origcmdline=`awk '{sub(/mtdparts.+)/,"");sub(/androidboot.bootloader=.+\...\...../,"");print}' $wkdir/${boot}.img-cmdline`
return
}

flashimg ()
{
$wkdir/mkbootimg --kernel $wkdir/${boot}.img-zImage --ramdisk $wkdir/${boot}.img-ramdisk.gz -o $wkdir/${boot}.img --cmdline "$origcmdline $KCMDline" --base `cat $wkdir/${boot}.img-base`
erase_image ${boot}
flash_image ${boot} $wkdir/${boot}.img
return
}

bindcache ()
{
if [ "`expr $cacheSizeKBytes \/ 1024`" -lt "30" ];
then
	cat > $wkdir/06BindCache << "EOF"
#!/system/bin/sh
# 2010-08-05 Firerat, bind mount cache to sd ext partition, and mount mtdblock4 for Clockwork recovery's use
busybox umount /cache
# Bind mount /sd-ext/cache ( or /system/sd/cache ) to /cache
if [ "`busybox egrep -q "sd-ext|/system/sd" /proc/mounts;echo $?`" = "0" ];
then
    sdmount=`busybox egrep "sd-ext|/system/sd" /proc/mounts|busybox awk '{ print $2 }'`
    cacheDir=${sdmount}/cache
else
	cacheDir=/data/cache
fi

if [ ! -d $cacheDir ];
then
	busybox install -m 771 -o 1000 -g 2001 -d $cacheDir
fi
    busybox mount -o bind $cacheDir /cache
if [ ! -d $cacheDir/dalvik-cache ];
then
	busybox install -m 771 -o 1000 -g 1000 -d $cacheDir/dalvik-cache
fi

if [ ! -d /dev/cache ];
then
	busybox install -d /dev/cache
fi

if [ "`grep -q \"/dev/cache\" /proc/mounts;echo $?`" != "0" ];
then
	busybox mount -t yaffs2 -o nosuid,nodev /dev/block/mtdblock4 /dev/cache
fi
if [ ! -d /dev/cache/recovery ];
then
	busybox install -m 770 -o 1000 -g 2001 -d /dev/cache/recovery
fi
if [ ! -L $cacheDir/recovery ];
then
	ln -s /dev/cache/recovery $cacheDir/recovery
fi
EOF
	if [ "`grep -q system /proc/mounts;echo $?`" != "0" ];
	then
		mount /system
	fi
	# grr, why rename init.d?
	if [ ! -e /system/etc/init.d -a -d /system/etc/super ];
	then
		ln -s /system/etc/super /system/etc/init.d
	fi
	install -m 700 -o 0 -g 0 -D $wkdir/06BindCache /system/etc/init.d/06BindCache
fi
return
}
AllInOnePatch ()
{
# start the 'all in one' with configured options ( if avaliable )
if [ -e $mapfile ];
then
	if [ "`grep -q aio $mapfile;echo $?`" = "0" ];
	then
		aioOPTs=`awk '/aio/ { $1 = "" ;print}' $mapfile`
		aiopatch=`ls -t $sdcard/fr-patch*txt|head -n 1`
	fi
	
	if [ "$aiopatch" != "" ];
	then
		aioversion=`awk '/Version\=\"Version/ { gsub(/\./,"");print $2+0 }' $aiopatch`
		if [ "$aioversion" -gt "136" ];
		then
			sh -x $aiopatch sdext $aioOPTs
		fi
	fi
fi
return
}

runparts ()
{
# hack runparts into ramdisk
# wish I didn't have to do this,
if [ "$boot" != "boot" ];
then
	return
fi
if [ "`ls /system/etc/init.d/*user*;echo $?`" = "0" ];
then
    return
fi

if [ -e "/system/xbin/busybox" -o -e "/system/xbin/xbin.sqf" ];
then
	mkdir rd
	cd rd
	zcat ../${boot}.img-ramdisk.gz |cpio -i
	if [ "`busybox egrep -qi \"service\ sysinit|run-parts\" init.rc;echo $?`" != "0" ];
	then
		sed '/class_start default/ i \ \ \ \ # start runparts script\n\ \ \ \ \/system\/bin\/sh \/system/runparts.sh\n' -i init.rc
		find * | cpio -o -H newc | gzip > ../${boot}.img-ramdisk.gz
	fi
	cd ../
	rm -r rd
	cat > /dev/runparts.sh << "EOF"
export PATH=/sbin:/system/sbin:/system/bin:/system/xbin
if [ -e "/system/xbin/logwrapper" ];
then
	/system/xbin/logwrapper /system/xbin/busybox echo -e "====================================================================\nShoehorned run-parts\nPlease Pester the ROM Dev to include run-parts in the ROM by default\n====================================================================" 
	/system/xbin/logwrapper /system/xbin/busybox run-parts /system/etc/init.d
else
	/system/xbin/busybox run-parts /system/etc/init.d
fi
EOF
	install -m 000 -o 0 -g 0 /dev/runparts.sh /system/runparts.sh
fi
return
}
#end functions

boot=$1
opt=$2
wkdir=/tmp
sdcard=/sdcard
mapfile=$sdcard/mtdpartmap.txt
mtdpart=/proc/mtd
dmesgmtdpart=/dev/mtdpartmap
logfile=$wkdir/recovery.log
dmesg=dmesg
testmode=n
if [ "$boot" = "recovery" -o "$boot" = "boot" ];
then
	if [ "$boot" = "recovery" ];
	then
		if [ "$opt" = "remove" ];
		then
			KCMDline=""
		else
			readdmesg
			recoverymode
			CreateCMDline
		fi
	else
		GetCMDline
	fi
	dumpimg	
	if [ "$boot" = "boot" ];
	then
		bindcache
		# for now do runparts patching as an option
		if [ "$opt" = "runparts" ];
		then
			runparts
		fi
		AllInOnePatch
	fi
	flashimg
else
    echo -e "CustomMTD Patcher v${version}\nNo Argument given, script needs either:\nboot or recovery" >> $logfile

	exit
fi
