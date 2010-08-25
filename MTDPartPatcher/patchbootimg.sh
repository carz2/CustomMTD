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

###############################################################################################

###############################################################################################


version=1.5.5
##

readdmesg ()
{
$dmesg|awk '/0x.+: "/ {sub(/-/," ");gsub(/"/,"");gsub(/0x/,"");printf $6" 0x"toupper ($3)" 0x"toupper ($4)"\n"}' > $dmesgmtdpart

# need a sanity check, what if recovery had been running for ages and the dmesg buffer had been filled?
for sanity in misc recovery boot system;do
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
    for partition in misc recovery boot;do
        eval ${partition}StartHex=`awk '/'$partition'/ {print $2}' $dmesgmtdpart`
        eval ${partition}EndHex=`awk '/'$partition'/ {print $3}' $dmesgmtdpart`
    done
    for partition in misc recovery boot;do
        eval StartHex=\$${partition}StartHex
        eval EndHex=\$${partition}EndHex
        eval ${partition}SizeKBytes=`expr \( $(printf %d $EndHex) - $(printf %d $StartHex) \) \/ 1024 `
        eval SizeKBytes=\$${partition}SizeKBytes
        eval ${partition}CL=`echo "${SizeKBytes}K@${StartHex}\(${partition}\)"`
    done
	CLInit="mtdparts=msm_nand:${miscCL},${recoveryCL},${bootCL}"
else
    echo -e "${boot} Patcher v${version}\npartition layout not found in dmesg\nand Dream/Magic not found\nPlease use ${boot} patcher early" >> $logfile
    exit
fi
return
}

recoverymode ()
{
if [ "$testmode" = "n" ];
then 
	mount $sdcard
fi
# new mtdpartmap config
if [ -e $mapfile ];
then
	busybox dos2unix $mapfile
	if [ "`egrep -q \"mtd|spl\" $mapfile;echo $?`" != "0" ];
	then
		systemMB=`awk '{print $1}' $mapfile`
		cacheMB=`awk '{print $2}' $mapfile`
		if [ "$cacheMB" -lt "2" ];
		then
			# need at least 2mb cache for recovery to not complain
			cacheMB=2
		fi
	else
		systemMB=`awk '/mtd/ {print $2}' $mapfile`
		cacheMB=`awk '/mtd/ {print $3}' $mapfile`
		FakeSPL=`awk '/spl/ {print $2}' $mapfile`
		
		if [ "$systemMB" = "" ];
		then
			if [ "`egrep -q "trout|sapphire" /proc/cmdline;echo $?`" = "0" ];
			then
		    	systemMB=90
			else
				echo "${boot} Patcher v${version}\nTrout/Sapphire not detected, please configure system size\n with in $mapfile\n e.g. echo \"mtd 115 2\" \> $mapfile" >> $logfile
				exit
			fi
		fi
		if [ "$cacheMB" = "" ];
		then
			cacheMB=2
		fi
	fi
else
	systemMB=90
	cacheMB=2
	FakeSPL=""
fi

if [ "$FakeSPL" = "" ];
then
	CLInit="$CLInit"
else
	CLInit="androidboot.bootloader=$FakeSPL $CLInit"
fi
return
}

CreateCMDline ()
{

if [ "$sain" = "y" ];
then
    systemStartHex=`awk '/system/ { print $2 }' $dmesgmtdpart`
    systemStartBytes=`printf %d $(awk '/system/ { print $2 }' $dmesgmtdpart)`
elif [ "`egrep -q "trout|sapphire" /proc/cmdline;echo $?`" = "0" ];
then
    systemStartBytes=48496640
    systemStartHex=`printf '%X' $systemStartBytes`
else
    echo -e "${boot} Patcher v${version}\n" >> $logfile
    echo "erm, shouldn't have got this far" >> $logfile
	exit
fi

if [ "$boot" = "recovery" ];
then
	systemSizeKBytes=`expr $systemMB \* 1024`
	systemBytes=`expr $systemSizeKBytes \* 1024`
else
	systemSizeHex=`awk '/system/ { print "0x"$2 }' $mtdpart`
	cacheSizeHex=`awk '/cache/ { print "0x"$2 }' $mtdpart`
	systemBytes=`printf '%d' $systemSizeHex`
	systemSizeKBytes=`expr $systemBytes \/ 1024`
fi

if [ "$boot" = "recovery" ];
then
	cacheSizeKBytes=`expr $cacheMB \* 1024`
	cacheBytes=`expr $cacheSizeKBytes \* 1024`
else
	cacheSizeHex=`awk '/cache/ { print "0x"$2 }' $mtdpart`
	cacheBytes=`printf '%d' $cacheSizeHex`
	cacheSizeKBytes=`expr $cacheBytes \/ 1024`
fi

cacheStartBytes=`expr $systemStartBytes + $systemBytes`
cacheStartHex=`printf '%X' $cacheStartBytes`

# data size is 'wildcard' -@ uses remaining space
DataKBytes=-
DataStartBytes=`expr $cacheStartBytes + $cacheBytes`
DataStartHex=`printf '%X' ${DataStartBytes}`

KCMDline="${CLInit},${systemSizeKBytes}k@${systemStartHex}(system),${cacheSizeKBytes}k@0x${cacheStartHex}(cache),${DataKBytes}@0x${DataStartHex}(userdata)"
return
}

flashimg ()
{
dump_image ${boot} $wkdir/${boot}.img
$wkdir/unpackbootimg $wkdir/${boot}.img $wkdir/
ls
origcmdline=`awk '{sub(/mtdparts.+)/,"");sub(/androidboot.bootloader=.+\...\...../,"");print}' $wkdir/${boot}.img-cmdline`
$wkdir/mkbootimg --kernel $wkdir/${boot}.img-zImage --ramdisk $wkdir/${boot}.img-ramdisk.gz -o $wkdir/${boot}.img --cmdline "$origcmdline $KCMDline" --base `cat $wkdir/${boot}.img-base`
if [ "$testmode" = "n" ];
then
	erase_image ${boot}
	flash_image ${boot} $wkdir/${boot}.img
fi
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
if [ "`egrep -q "sd-ext|/system/sd" /proc/mounts;echo $?`" = "0" ];
then
    sdmount=`egrep "sd-ext|/system/sd" /proc/mounts|awk '{ print $2 }'`
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
	#TODO inject a run-parts into init.rc,
	# assuming the init.rc has an import and the init is compatible
	install -m 700 -o 0 -g 0 -D $wkdir/06BindCache /system/etc/init.d/06BindCache
fi
return
}
AllInOnePatch ()
{
#start the 'all in one' with configured options ( if avaliable )
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
			sh +x $aiopatch sdext $aioOPTs
		fi
	fi
fi
return
}
testrun ()
{
if [ "$testmode" = "y" ];
then
	for partition in misc recovery boot system cache;do
		eval SizeKBytes=\$${partition}SizeKBytes
		eval ${partition}SizeHex="$( printf %X `expr $SizeKBytes \* 1024`|awk '{printf "%08s",$1}')"
	done
	eval dataSizeHex=$(printf %x `expr $(printf %d $(awk '/'userdata'/ {print $3}' $dmesgmtdpart)) - $(printf %d 0x${DataStartHex})`)
# lol, I should tidy that up 
	if [ "$boot" = "recovery" ];
	then
	$dmesg |awk '/Kernel command line/ {sub (/serialno=.+\ a/,"serialno=XXXXXXXXXXXX a"); print $0}' |tee -a $logfile
	fi
	echo "dev: size erasesize name " > $mtdpart
	echo "mtd0: $miscSizeHex 00020000 \"misc\"" >> $mtdpart
	echo "mtd1: $recoverySizeHex 00020000 \"recovery\"" >> $mtdpart
	echo "mtd2: $bootSizeHex 00020000 \"boot\"" >> $mtdpart
	echo "mtd3: $systemSizeHex 00020000 \"system\"" >> $mtdpart
	echo "mtd4: $cacheSizeHex 00020000 \"cache\"" >> $mtdpart
	echo "mtd5: $dataSizeHex 00020000 \"userdata\"" >> $mtdpart
	echo "$boot"|tee -a $logfile
	cat mtd|awk --non-decimal-data '{printf "%-7s %-10s %-10s %-10s % 8.3f %s",$1,$2,$3,$4,(("0x"$2)+0)/1048576,"M""\n"}'|sed s/\ 0.000\ M/size\ M/|tee -a $logfile
	echo "$origcmdline $KCMDline"|tee -a $logfile
fi
return
}
#end functions

if [ "$1" = "test" ];
then
	if [ "$#" = "1" ];
	then
		# this is testing on the actual device
		wkdir=/tmp
		dmesg="dmesg"
	else
		# this is testing a dmesg log file
		wkdir=`pwd`
		sdcard=$wkdir/sdcard
		dmesg="cat $2"
	fi
	mapfile=$wkdir/mtdpartmap.txt
	mtdpart=$wkdir/mtd
	dmesgmtdpart=$wkdir/mtdpartmap
	logfile=$wkdir/recovery.log
	echo mapfile=$wkdir/mtdpartmap.txt
	echo mtdpart=$wkdir/mtd
	echo dmesgmtdpart=$wkdir/mtdpartmap
	echo logfile=$wkdir/recovery.log
	testmode=y
	Mode=recovery
	boot=recovery
	readdmesg
	# this is going to fail on a device as busybox awk doesn't have strtonum
	awk '{printf "%-9s %s %s %8.3f %s",$1,$2,$3,(strtonum($3)-strtonum($2))/1048576,"M\n"}' $dmesgmtdpart|tee -a $logfile
	recoverymode
	CreateCMDline
	testrun
	flashimg
	Mode=boot
	boot=boot
	readdmesg
	$dmesg|sed s/serialno=.*\ a/serialno=XXXXXXXXXX\ a/g>$wkdir/dmesg
    CreateCMDline
    testrun
	flashimg
	cd $wkdir
	tardir=`$dmesg|awk -F\:\  '/Machine:/ {print $2}'`_CustomMTD
	mkdir $tardir
	for i in dmesg mtd mtdpartmap boot* recovery*;do
		mv $i $tardir
	done
	tar -cz $tardir -f ${sdcard}/${tardir}.tar.gz
	exit
fi

Mode=$1
wkdir=/tmp
sdcard=/sdcard
mapfile=$sdcard/mtdpartmap.txt
mtdpart=/proc/mtd
dmesgmtdpart=/dev/mtdpartmap
logfile=$wkdir/recovery.log
dmesg=dmesg
testmode=n
if [ "$Mode" = "recovery" -o "$Mode" = "boot" ];
then
	readdmesg
	if [ "$Mode" = "recovery" ];
	then
		boot=recovery
		recoverymode
	else
		if [ "$Mode" = "boot" ];
		then
			boot=boot
		fi
	fi
	CreateCMDline
	flashimg
	
	if [ "$Mode" = "boot" ];
	then
		bindcache
	AllInOnePatch
	fi
else
    echo -e "CustomMTD Patcher v${version}\nNo Argument given, script needs either:\nboot, recovery or test [dmesglogfile] )" >> $logfile

	exit
fi
