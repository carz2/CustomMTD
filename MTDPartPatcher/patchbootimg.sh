#!/sbin/sh
# patchbootimg.sh
# 2010-06-24 Firerat
# patch boot.img with custom partition table
# Credits lbcoder
# http://forum.xda-developers.com/showthread.php?t=704560
#
# https://github.com/Firerat/CustomMTD

version=1.5.8-Beta
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
    CLInit="$CLInit mtdparts=msm_nand:"
    for partition in `cat $dmesgmtdpart|awk '{print $1}'`;do
        eval ${partition}StartHex=`awk '/'$partition'/ {print $2}' $dmesgmtdpart`
        eval ${partition}EndHex=`awk '/'$partition'/ {print $3}' $dmesgmtdpart`
    done

    #Get resizable nand size ( mb )
    SCD_Total=0
    for partition in system cache userdata;do
        eval StartHex=\$${partition}StartHex
        eval EndHex=\$${partition}EndHex
        eval ${partition}SizeMBytes=`expr \( $(printf %d $EndHex) - $(printf %d $StartHex) \) \/ 1048576`
    done
SCD_Total=`echo|awk '{printf "%g",'$systemSizeMBytes' + '$cacheSizeMBytes' + '$userdataSizeMBytes' }'`

    for partition in `cat $dmesgmtdpart|awk '!/system|cache|userdata/ {print $1}'`;do
        eval StartHex=\$${partition}StartHex
        eval EndHex=\$${partition}EndHex
        eval ${partition}SizeKBytes=`expr \( $(printf %d $EndHex) - $(printf %d $StartHex) \) \/ 1024 `
        eval SizeKBytes=\$${partition}SizeKBytes
        CLInit="${CLInit}`echo \"${SizeKBytes}K@${StartHex}(${partition})\"`,"
    done
    CLInit="`echo $CLInit|sed s/,\$//`"
else
    echo -e "${boot} Patcher v${version}\npartition layout not found in dmesg" >> $logfile
    exit
fi
return
}

recoverymode ()
{
if [ ! -e $mapfile -a "$opt" != "testrun" ];
then
    echo "${boot} Patcher v${version}\n$mapfile does not exist,\nplease create it with system and cache size, e.g. echo \"mtd 115 2\" \> $mapfile" >> $logfile
    exit
else
    busybox dos2unix $mapfile
    systemMB=`awk '/mtd/ {print $2}' $mapfile`
    if [ "$systemMB" = "0" ];
    then
        removecmtd
    fi
    cacheMB=`awk '/mtd/ {print $3}' $mapfile`
    FakeSPL=`awk '/spl/ {print $2}' $mapfile`

    # Meh, need whole numbers
    if [ "`echo|awk '{printf "%d" '$cacheMB' * 10}'`" -lt "15" -o "$cacheMB" = "" ];
    then
    # need at least 2mb cache for recovery to not complain
        cacheMB=2
    fi

    if [ "$systemMB" = "" ];
    then
        if [ "$opt" = "testrun" ];
        then
            systemMB=93.75
            echo "inserted system size for testrun"
        else
            echo "${boot} Patcher v${version}\nPlease configure system size\n with in $mapfile\n e.g. echo \"mtd 115 2\" \> $mapfile" >> $logfile
            exit
        fi
    fi

    # make sure we are sizing in units of 128k ( 0.125 MB )
    for UserSize in $systemMB $cacheMB;do
       expr $(echo|awk '{printf "%g", '$UserSize' / 0.125}') \* 1
       if [ "$?" != "0" ];
       then
           echo "$UserSize not divisable by 0.125" >> $logfile
           #TODO better error msg, I want to redo all feedback anyway
           exit
       fi
    done

    if [ "$FakeSPL" = "" ];
    then
        CLInit="$CLInit"
    else
        CLInit="androidboot.bootloader=$FakeSPL $CLInit"
    fi
fi
return
}
checksizing ()
{
usertotal=`echo|awk '{printf "%f",'$systemMB' + '$cacheMB'}'`
userdatasize=`echo|awk '{printf "%f",'$SCD_Total' - '$usertotal'}'`
# check if user wants to override min data size
if [ "`grep -q -i "anydatasize" $mapfile;echo $?`" != "0" ];
then
    # a freshly installed ROM should still boot with 50mb data
    # However trickery to get things on to /sd-ext may be required
    mindatasize=50
else
    # Might change this to 2, user needs to know what they are doing anyway
    mindatasize=0
fi

if [ "`echo|awk '{printf "%d", '$userdatasize'}'`" -lt "$mindatasize" ];
then
    echo "data size will be less than 50mb,, exiting"
    exit
fi
return
}

CreateCMDline ()
{
systemStartHex=`awk '/system/ { print $2 }' $dmesgmtdpart`
systemStartBytes=`printf %d $(awk '/system/ { print $2 }' $dmesgmtdpart)`
systemSizeKBytes=`echo|awk '{printf "%d",'$systemMB' * 1024}'`
systemBytes=`echo|awk '{printf "%f",'$systemSizeKBytes' * 1024}'`

cacheSizeKBytes=`echo|awk '{printf "%d",'$cacheMB' * 1024}'`
cacheBytes=`echo|awk '{printf "%f",'$cacheSizeKBytes' * 1024}'`
cacheStartBytes=`echo|awk '{printf "%f",'$systemStartBytes' + '$systemBytes'}'`
cacheStartHex=`echo|awk '{printf "%X",'$cacheStartBytes'}'`

DataStartBytes=`echo|awk '{printf "%f",'$cacheStartBytes' + '$cacheBytes'}'`
DataStartHex=`echo|awk '{printf "%X",'$DataStartBytes'}'`
DataBytes=`echo|awk '{printf "%f",'$(printf '%d' ${userdataEndHex})' - '$DataStartBytes'}'`
DataKBytes=`echo|awk '{printf "%d",'$DataBytes' / 1024}'`

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
origcmdline=`awk '{gsub(/\ .\ /,"");sub(/mtdparts.+)/,"");sub(/androidboot.bootloader=.+\ /,"");print}' $wkdir/${boot}.img-cmdline|awk '{$1=$1};1'`
return
}

flashimg ()
{
$1 $wkdir/mkbootimg --kernel $wkdir/${boot}.img-zImage --ramdisk $wkdir/${boot}.img-ramdisk.gz -o $wkdir/${boot}.img --cmdline "$origcmdline $KCMDline" --base `cat $wkdir/${boot}.img-base`
$1 erase_image ${boot}
$1 flash_image ${boot} $wkdir/${boot}.img
return
}

bindcache ()
{
cacheSizeKBytes=`df |awk '/ \/cache$/ {print $2}'`
if [ "`expr $cacheSizeKBytes \/ 1024`" -lt "15" ];
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

removecmtd ()
{
dumpimg
KCMDline=""
flashimg
exit
}
#end functions
me=$0
boot=$1
opt=$2
wkdir=/tmp
sdcard=/sdcard
mapfile=$sdcard/mtdpartmap.txt
mtdpart=/proc/mtd
dmesgmtdpart=/dev/mtdpartmap
logfile=$wkdir/recovery.log
dmesg=dmesg
if [ "$boot" = "test" ];
then
    dmesg > /sdcard/cMTD-testoutput.txt
    busybox sed s/serialno=.*\ a/serialno=XXXXXXXXXX\ a/g -i /sdcard/cMTD-testoutput.txt
    sh -x $me recovery testrun >> /sdcard/cMTD-testoutput.txt 2>&1
    busybox unix2dos /sdcard/cMTD-testoutput.txt
    exit
fi

if [ "$opt" = "remove" ];
then
    removecmtd
fi
if [ "$boot" = "recovery" ];
then
    recoverymode
    readdmesg
    checksizing
    CreateCMDline
elif [ "$boot" = "boot" ];
then
    GetCMDline
    bindcache
else
    echo -e "CustomMTD Patcher v${version}\nNo Argument given, script needs either:\nboot or recovery" >> $logfile
    exit
fi
dumpimg
if [ "$opt" = "testrun" ];
then
    flashimg echo
else
    flashimg
fi
