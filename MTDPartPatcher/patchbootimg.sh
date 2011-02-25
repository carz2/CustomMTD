#!/sbin/sh
# patchbootimg.sh
# 2010-06-24 Firerat
# patch boot.img with custom partition table
# Credits lbcoder
# http://forum.xda-developers.com/showthread.php?t=704560
#
# https://github.com/Firerat/CustomMTD

version=1.5.9-Alpha3
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
if [ "$sain" = "n" ];
then
    echo "Error1=Error $sanity not found in dmesg" >> $logfile
    echo "success=false" >> $logfile
    exit
else
    CLInit="$CLInit mtdparts=msm_nand:"
    for partition in `cat $dmesgmtdpart|awk '{print $1}'`;do
        eval ${partition}StartHex=`awk '/'$partition'/ {print $2}' $dmesgmtdpart`
        eval ${partition}EndHex=`awk '/'$partition'/ {print $3}' $dmesgmtdpart`
    done

    # figure out the partition order of system cache and userdata
    for partition in system cache userdata;do
        eval StartHex=\$${partition}StartHex
        for part in `cat $dmesgmtdpart|awk '{print $1}'`;do
            if [ "$StartHex" = "`awk '/'$part'/ {print $3}' $dmesgmtdpart`" ];
            then
                eval ${partition}StartsAtEndOf=$part
                break
            fi
        done
    done

    # now check if system, cache and userdata are consecutive
    if [ "$cacheStartsAtEndOf" = "system" -a "$userdataStartsAtEndOf" = "cache" ];
    then
        consecutive=yes
        exclude="system|cache|userdata"
    else
        if [ "$userdataStartsAtEndOf" = "system" ];
        then
            echo "Error1=none consecutive partitions" >> $logfile
            echo "Error2=detected, can not proceed" >> $logfile
            echo "success=false" >> $logfile
            exit
            consecutive=SD
            exclude="system|userdata"
        else
            echo "Error1=none consecutive partitions" >> $logfile
            echo "Error2=detected, can not proceed" >> $logfile
            echo "success=false" >> $logfile
            exit
            consecutive=CD
            exclude="cache|userdata"
        fi
    fi
    #Get resizable nand size ( mb )
    SCD_Total=0
    for partition in system cache userdata;do
        eval StartHex=\$${partition}StartHex
        eval EndHex=\$${partition}EndHex
        eval Sizebytes=`expr $(printf %d $EndHex) - $(printf %d $StartHex)`
        eval ${partition}SizeMBytes=`echo |awk '{printf "%f", '$Sizebytes' / 1048576}'`
        eval SizeMB=\$${partition}SizeMBytes
        partition=`echo $partition|sed s/user//`
echo $partition
        echo|awk '{printf "%s%s%s%-9s%s%9.3f %s","Orig_","'$partition'","Size=","'$partition'","=",'$SizeMB',"MB\n"}' >> $logfile
    done
    SCD_Total=`echo|awk '{printf "%g",'$systemSizeMBytes' + '$cacheSizeMBytes' + '$userdataSizeMBytes' }'`
    for partition in `cat $dmesgmtdpart|awk '!/'$exclude'/ {print $1}'`;do
        eval StartHex=\$${partition}StartHex
        eval EndHex=\$${partition}EndHex
        eval ${partition}SizeKBytes=`expr \( $(printf %d $EndHex) - $(printf %d $StartHex) \) \/ 1024 `
        eval SizeKBytes=\$${partition}SizeKBytes
        if [ "$partition" = "cache" -a "$consecutive" = "SD" ];
        then
            partition=system
        fi
        CLInit="${CLInit}`echo \"${SizeKBytes}K@${StartHex}(${partition})\"`,"
    done
    CLInit="`echo $CLInit|sed s/,\$//`"
fi
return
}

readconfig ()
{
#TODO, make new config format (prop style)
if [ ! -e $mapfile -a "$opt" != "testrun" ];
then
#TODO write a default config and point at it while we have users attention 
    cat >> $logfile << "EOF"
Error1=/sdcard/mtdpartmap.txt
Error2=does not exist please create
Error3=it with system and cache size
success=false
EOF
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
           echo "Error1=$UserSize not divisable by 0.125" >> $logfile
           echo "success=false" >> $logfile
           exit
       fi
    done

    if [ "$FakeSPL" = "" ];
    then
        CLInit="$CLInit"
    else
        CLInit="androidboot.bootloader=$FakeSPL $CLInit"
    fi
    LastRecoverymd5sum=`awk '/recoverymd5/ {print $2}'`
    if [ "$LastRecoverymd5sum" = "" ];
    then
        LastRecoverymd5sum=`md5sum /dev/mtd/$(awk -F: '/recovery/ {print $1}' /proc/mtd)ro|awk '{print $1}'`
        echo "recoverymd5 $LastRecoverymd5sum" >> $mapfile
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
    cat >> $logfile << "EOF"
Error1=data will be less than 50mb, add
Error2="anydatasize" to mtdpartmap.txt
Error3=if you wish to skip this check
success=false
EOF
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
if [ "$consecutive" = "SD" ];
then
    cacheStartHex=`echo|awk '{printf "%X",'$systemStartBytes'}'`
elif [ "$consecutive" = "CD" ];
then
    cacheStartHex=`awk '/cache/ {printf "%X",$2 }' $dmesgmtdpart`
else
    cacheStartBytes=`echo|awk '{printf "%f",'$systemStartBytes' + '$systemBytes'}'`
    cacheStartHex=`echo|awk '{printf "%X",'$cacheStartBytes'}'`
fi

dataStartBytes=`echo|awk '{printf "%f",'$cacheStartBytes' + '$cacheBytes'}'`
dataStartHex=`echo|awk '{printf "%X",'$dataStartBytes'}'`
dataSizeBytes=`echo|awk '{printf "%f",'$(printf '%d' ${userdataEndHex})' - '$dataStartBytes'}'`
dataSizeKBytes=`echo|awk '{printf "%d",'$dataSizeBytes' / 1024}'`

if [ "$consecutive" = "yes" ];
then
    KCMDline="${CLInit},${systemSizeKBytes}k@${systemStartHex}(system),${cacheSizeKBytes}k@0x${cacheStartHex}(cache),${dataSizeKBytes}k@0x${dataStartHex}(userdata)"
else
    KCMDline="${CLInit},${cacheSizeKBytes}k@0x${cacheStartHex}(cache),${dataSizeKBytes}k@0x${dataStartHex}(userdata)"
fi
for MTDPart in system cache data;do
    eval SizeKB=\$${MTDPart}SizeKBytes
    eval SizeMB=`echo|awk '{printf "%f",'$SizeKB'/1024}'`
    echo|awk '{printf "%s%s%s%-9s%s%9.3f %s","New_","'$MTDPart'","Size=","'$MTDPart'","=",'$SizeMB',"MB\n"}' >> $logfile
done
return
}

GetCMDline ()
{
KCMDline="mtdparts`cat /proc/cmdline|awk -Fmtdparts '{print $2}'`"
if [ "$KCMDline" = "mtdparts" ];
then
    KCMDline=""
fi
    for MTDPart in system cache userdata;do
        SizeMB=$(printf %d `awk '/'${MTDPart}'/ {print "0x"$2}' /proc/mtd`|awk '{printf "%f", $1 / 1048576}')
        MTDPart=`echo $MTDPart|sed s/user//`
        echo|awk '{printf "%s%s%s%-9s%s%9.3f %s","New_","'$MTDPart'","Size=","'$MTDPart'","=",'$SizeMB',"MB\n"}' >> $logfile
    done
return
}

dumpimg ()
{
mtdblk=`awk -F: '/'$boot'/ {print $1}' /proc/mtd`ro
$wkdir/unpackbootimg /dev/mtd/${mtdblk} $wkdir/
origcmdline=`awk '{gsub(/\ .\ /,"");sub(/mtdparts.+)/,"");sub(/androidboot.bootloader=.+\ /,"");print}' $wkdir/${mtdblk}-cmdline|awk '{$1=$1};1'`
return
}

flashimg ()
{
$1 $wkdir/mkbootimg --kernel $wkdir/${mtdblk}-zImage --ramdisk $wkdir/${mtdblk}-ramdisk.gz -o $wkdir/${boot}.img --cmdline "$origcmdline $KCMDline" --base `cat $wkdir/${mtdblk}-base`
imagemd5=`md5sum $wkdir/${boot}.img|awk '{print $1}'`
$1 erase_image ${boot}
$1 flash_image ${boot} $wkdir/${boot}.img
if [ "$imagemd5" = "`md5sum /dev/mtd/${mtdblk}|awk '{print $1}'`" ];
then
    echo "success=true" >> $logfile
    if [ "$boot" = "recovery" ];
    then
        sed s/recoverymd5.*+/recoverymd5\ $imagemd5/ -i $mapfile
    fi
    exit
else
    echo "Error1=Writing $boot failed" >> $logfile
    echo "Error2=Make sure you have an unlocked" >> $logfile
    echo "Error3=bootloader (aka spl or hboot)" >> $logfile
    echo "success=false" >> $logfile
    exit
fi
return
}

bindcache ()
{
#TODO get rid of this script in favour of setting DOWNLOAD_CACHE
# use a optional patch for ROMs which do not support DOWNLOAD_CACHE by default
if [ "`grep -q system /proc/mounts;echo $?`" != "0" ];
then
    mount /system
fi
# first check if 06mountdl is present ( a cm7 script )
if [ -e /system/etc/init.d/06mountdl ];
then
    if [ "`grep -q \#FR\# /system/etc/init.d/06mountdl;echo $?`" != "0" ];
    then
        fix06mountdl
    fi
    return
fi
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
    # grr, why rename init.d?
    if [ ! -e /system/etc/init.d -a -d /system/etc/super ];
    then
        ln -s /system/etc/super /system/etc/init.d
    fi
    install -m 700 -o 0 -g 0 -D $wkdir/06BindCache /system/etc/init.d/06BindCache
fi
return
}

fix06mountdl ()
{
# CM7's 06mountdl is great, but.. 
# currently ( as per commit 2a742afd1757b1cd89f97978ac4ddf959206e3cc )
# it will use data for DOWNLOAD_CACHE if /cache has less than 20mb free space
# Trouble is, this more than doubles the space required to successfully install an app
# a 15mb app would need at least 30mb + 10% of total data
# so assuming 200mb data partition, you would need:
# app size| data | sd-ext or cache
#     1   |  22  |   21  |
#     5   |  30  |   25  |
#    15   |  50  |   35  |
#    20   |  60  |   40  |
#    30   |  80  |   50  |
#    50   | 120  |   70  |
# this script considers using sd-ext ( if avaialable )
# and will only use /data if it has more than twice as much free space as cache
#
# Oh, and things were breaking because 06BindCach was running before 06mountdl
# and 06mountdl wasn't creating the download dir on the 'fake' cache
# this fixes this issue, but tbh I'm being a little cheeky installing this
# so included an undo feature
sed -e s/^/#FR#/ -e s/#FR##\!/#\!/ > /dev/06mountdl
cat >> /dev/06mountdl << "EOF"
# state that I tainted it
echo "06mountdl modified by Firerat"
echo "run 06mountdl with -undo"
echo "e.g."
echo "$0 -undo"
echo "( as root ! )"
echo "to revert to original"
if [ "$1" = "-undo" ];
then
    mount -o remount,rw /system
    grep -E "#\!/system|#FR#" $0|sed s/#FR#// > $0
    mount -o remount,ro /system
    echo "Firerat tainted 06mountdl removed"
    echo "reboot to see changes"
    exit
fi
avail ()
{
partition=`echo $1|sed s/[^a-zA-Z0-9]//g`
eval ${partition}_free=$(df |awk '$6 == "/'$1'" {printf $4}')
eval checkzero=\$${partition}_free
if [ "$checkzero" = "" ];
then
    eval ${partition}_free="0"
fi
}
for partition in sd-ext data cache;do
    avail $partition
done
# Prioritise the sd-ext ( if avialable )
# only use data if cache is too small
minDLCache=`expr 50 \* 1024` # 50mb , max market d/l is currently 50mb
#TODO check is sysdex will be going to cache
if [ "$sdext_free" -gt "$cache_free" ];
then
    AltDownloadCache="/sd-ext/download"
elif [ "$cache_free" -lt "$minDLCache" -a "$data_free" -gt "`expr $cache_free \* 2`" -o "$data_free" -gt "`expr $minDLCache \* 2`" ];
then
    AltDownloadCache="/data/download"
    # TODO Factor in the 10% 'reserve'
else
    # do nothing
    exit
fi

if [ ! -e "$AltDownloadCache" ];
then
    install -m 771 -o 1000 -g 2001 -d $AltDownloadCache
fi
busybox mount -o bind $AltDownloadCache $DOWNLOAD_CACHE
exit
EOF
install -m 700 -o 0 -g 0 /dev/06mountdl /system/etc/init.d/06mountdl
return
}
removecmtd ()
{
dumpimg
KCMDline=""
flashimg
for MTDPart in system cache userdata;do
    SizeMB=$(printf %d `awk '/'${MTDPart}'/ {print "0x"$2}' /proc/mtd`|awk '{printf "%f", $1 / 1048576}')
    MTDPart=`echo $MTDPart|sed s/user//`
    echo|awk '{printf "%s%s%s%-9s%s%9.3f %s","Orig_","'$MTDPart'","Size=","'$MTDPart'","=",'$SizeMB',"MB\n"}' >> $logfile
done
echo "success=true" >> $logfile
exit
}
Optimum ()
{
# this function will look at the existing installation and write an mtdpartmap.txt based on used size
# mount everything
mount -a
for partition in system cache;do
    eval ${partition}Opt=`df |awk '/\/'${partition}'/ {printf "%d", ($3 / 128) + 2}'|awk '{printf "%.3f", ( $1 * 128 ) / 1024 }'`
# meh, lazy pipes, I should learn to use awk properly
done
echo mtd $systemOpt $cacheOpt
# TODO
# backup existing ROM,
# patch recovery's init.rc,
# erase_image ( kang one for RA ),
# do restore feature,
# stop recovery from Auto rebooting after scripted restore
# print what we did ( i.e. new sizes )

# and one day I will look at msm_nand ko  ^^ is cheap n easy
return
}

AutoPatch ()
{
# this function will compare users defined settings with current running recovery
# if they are different it will patch recovery
# if they match it will check the installed recovery's md5sum against the logged md5sum, and patch if they don't match
# if all those conditions are met, it will patch the boot.img with the running recovery's layout
# should have done this ages ago
readconfig
for MTDPart in system cache;do
    eval ${MTDPart}SizeMB=$(printf %d `awk '/'${MTDPart}'/ {print "0x"$2}' /proc/mtd`|awk '{printf "%f", $1 / 1048576}')
done
if [ "$systemMB" != "$systemSizeMB" -o "$cacheMB" != "$cacheSizeMB" ];
then
    boot=recovery
else
    Recoverymd5sum=`md5sum /dev/mtd/$(awk -F: '/recovery/ {print $1}' /proc/mtd)ro|awk '{print $1}'`
    LastRecoverymd5sum=`awk '/recoverymd5/ {print $2}'`
    if [ "$Recoverymd5sum" != "$LastRecoverymd5sum" ];
    then
        boot=recovery
    else
        boot=boot
    fi
fi
#TODO check spl spoof ( not that spl spoofing has any pratical use anymore, but may be needed for old roms, or die hard 1.33.2003 fans )
return
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
logfile=$wkdir/cMTD.log
dmesg=dmesg
if [ "$#" = "3" ];
then
    # hack in a desktop test mode,
    # 1st opt is test, 2nd Anything, 3nd opt is dmesg sample
    # yeap, its crap, but will do for now
    wkdir=`pwd`
    sdcard=`pwd`
    mapfile=$sdcard/mtdpartmap.txt
    mtdpart=`pwd`/mtd
    dmesgmtdpart=`pwd`/mtdpartmap
    logfile=$wkdir/cMTD.log
    dmesg="cat $3"
fi
if [ "$boot" = "test" ];
then
    $dmesg > $sdcard/cMTD-testoutput.txt
    busybox sed s/serialno=.*\ a/serialno=XXXXXXXXXX\ a/g -i $sdcard/cMTD-testoutput.txt
    sh -x $me recovery testrun $3 >> $sdcard/cMTD-testoutput.txt 2>&1
    busybox unix2dos $sdcard/cMTD-testoutput.txt
    exit
fi

#AutoPatch

echo "Mode=$boot" > $logfile

if [ "$boot" = "remove" ];
then
    boot=recovery
    removecmtd
fi
if [ "$boot" = "recovery" ];
then
    readconfig
    readdmesg
    checksizing
    CreateCMDline
elif [ "$boot" = "boot" ];
then
    GetCMDline
    bindcache
else
    echo "Error1=No Argument given" >> $logfile
    echo "Error2=script needs either:" >> $logfile
    echo "Error3=boot or recovery" >> $logfile
    echo "success=false" >> $logfile
    exit
fi
dumpimg
if [ "$opt" = "testrun" ];
then
    sed s/$boot/testrun/ -i $logfile 
    flashimg echo
else
    flashimg
fi
