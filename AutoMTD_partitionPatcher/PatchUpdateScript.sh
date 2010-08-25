#!/bin/sh
# 2010-07-01 Firerat
# Patch update(r)-script to run boot.img MTD Patcher
#
version=1.5.5
startdir=`pwd`

me=$0
echo $me
if [ "`echo $me|cut -c 1`" != "/" ];
then
	AutoMTDPatchTools=`pwd`/`dirname $me`/AutoMTDPatchTools
else
	AutoMTDPatchTools=`dirname $me`/AutoMTDPatchTools
fi
echo $AutoMTDPatchTools
ROMZIP=$1

TOOLS=MTDPartPatcher
ScriptPath=META-INF/com/google/android/
ScriptType=0

if [ "$#" != "1" ];
then
	echo "Custom Partition Layout - ROM zip patcher"
	echo "Version $version"
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo "usage"
	echo "$me <ROM Zip to patch>"
	exit 1
fi

unziprom ()
{
if [ "`unzip -l $ROMZIP|egrep -q \"update-script|updater-script\";echo $?`" != "0" ];
then
	echo "$ROMZIP does not appear to be a valid recovery flashable zip file"
	echo "NB, make sure you have provided the full path !"
	exit 1
else
	if [  -e "`basename $ROMZIP .zip`" ];
	then
		rm -rf `basename $ROMZIP .zip`
	fi
	
	tempdir=`basename $ROMZIP .zip`
	install -d $tempdir
	cp $ROMZIP ${tempdir}/
	ROMZIP=`basename $ROMZIP`
	cd $tempdir
	tar vxf ${AutoMTDPatchTools}/${TOOLS}.tar.gz
fi
}
main ()
{
for update in update updater;do
unzip $ROMZIP ${ScriptPath}${update}-script
if [ "$?" = "0" ];
then
	ScriptType=$update
	break
fi
done

if [ "$ScriptType" = "0" ];
then
	echo "No update(r)-script found in zip, are you sure this is a flashable ROM?"
	exit 1

elif [ "$ScriptType" = "update" ];
then
	UpdateScript
	return
elif [ "$ScriptType" = "updater" ];
then
	UpdaterScript
	return
else
	echo "Something went very wrong.."
	echo "looked like I found the script, but I don't recongnise it..."
	exit 2
fi
return
}
	
UpdateScript ()
{
sed \
-e '/write_raw_image .*BOOT.*/ a copy_dir PACKAGE:MTDPartPatcher TMP:\nset_perm_recursive 0 0 0744 0700 TMP:\nrun_program TMP:patchbootimg.sh boot' \
-i ${ScriptPath}${ScriptType}-script
#-e 's/write_raw_image PACKAGE:boot.img/write_raw_image TMP:boot.img/' \
#-i ${ScriptPath}${ScriptType}-script

return
}

UpdaterScript ()
{
sed \
"/write_raw_image.*\"boot\".*/ a ui_print\(\"Auto\ CustomMTD\ v${version}\"\)\;\npackage_extract_dir\(\"MTDPartPatcher\",\ \"/tmp\"\)\;\nset_perm\(0,\ 0,\ 0777,\ \"\/tmp\/patchbootimg.sh\"\)\;\nset_perm\(0,\ 0,\ 0777,\ \"\/tmp\/unpackbootimg\"\)\;\nset_perm\(0,\ 0,\ 0777,\ \"\/tmp\/mkbootimg\"\)\;\nrun_program\(\"\/tmp\/patchbootimg.sh\",\ \"boot\"\)\;\nui_print\(\"Patching\ boot\ image...\"\)\;\nui_print\(\"Auto\ CustomMTD\ Patched\"\)\;" \
-i ${ScriptPath}${ScriptType}-script

return
}
zipsign ()
{
zip -r $ROMZIP META-INF $TOOLS  
echo "signing $ROMZIP...."
outputzip=`basename $ROMZIP .zip`-AutoMTD.zip
java -jar ${AutoMTDPatchTools}/signapk.jar ${AutoMTDPatchTools}/testkey.x509.pem ${AutoMTDPatchTools}/testkey.pk8 $ROMZIP ${startdir}/${outputzip}
echo "signing $ROMZIP complete"
echo "signed file is ${outputzip}"

return
}
TidyUp ()
{
cd ${startdir}
rm -r ${tempdir}
return
}
zip_or_img ()
{
for ext in zip img;do
	if [ "`echo $ROMZIP|grep -q $ext\$;echo $?`" = "0" ];
	then
		mode=$ext
		break
	fi
done
if [ "$mode" = "" ];
then
	echo "$ROMZIP .. unknown file extension"
	echo "can't do anything :( "
	exit 1
fi
return
}
mkrecovery_zip ()
{
startdir=`pwd`
tempdir=${startdir}/`basename $ROMZIP .img`
updaterscript=${tempdir}/META-INF/com/google/android/updater-script
updaterbinary=${tempdir}/META-INF/com/google/android/update-binary
install -d $tempdir
cp $ROMZIP $tempdir
install -D $AutoMTDPatchTools/update-binary $updaterbinary
echo "ui_print(\"`basename $ROMZIP`\");" > $updaterscript
echo "assert(package_extract_file(\"`basename $ROMZIP`\", \"/tmp/recovery.img\")," >> $updaterscript
echo "       write_raw_image(\"/tmp/recovery.img\", \"recovery\")," >> $updaterscript
echo "ui_print(\"Auto CustomMTD v${version}\");" >> $updaterscript
echo "package_extract_dir(\"MTDPartPatcher\", \"/tmp\");" >> $updaterscript
echo "set_perm(0, 0, 0777, \"/tmp/patchbootimg.sh\");" >> $updaterscript
echo "set_perm(0, 0, 0777, \"/tmp/unpackbootimg\");" >> $updaterscript
echo "set_perm(0, 0, 0777, \"/tmp/mkbootimg\");" >> $updaterscript
echo "run_program(\"/tmp/patchbootimg.sh\", \"recovery\");" >> $updaterscript
echo "ui_print(\"Patching recovery image...\");" >> $updaterscript
echo "ui_print(\"Auto CustomMTD Patched\");" >> $updaterscript
echo "       delete(\"/tmp/recovery.img\"));" >> $updaterscript
echo "show_progress(0.100000, 0);" >> $updaterscript
cd $tempdir
tar vxf ${AutoMTDPatchTools}/${TOOLS}.tar.gz
ROMZIP=${startdir}/`basename $ROMZIP .img`.zip
outputzip=${startdir}/`basename $ROMZIP .zip`_AutoMTD.zip
zip -r $ROMZIP *
cd ${startdir}
java -jar ${AutoMTDPatchTools}/signapk.jar ${AutoMTDPatchTools}/testkey.x509.pem ${AutoMTDPatchTools}/testkey.pk8 $ROMZIP ${outputzip}
rm $ROMZIP
return
}
zip_or_img
if [ "$mode" = "zip" ];
then
	unziprom
	main
	zipsign
	TidyUp
	exit 0
fi
if [ "$mode" = "img" ];
then
	mkrecovery_zip
	TidyUp
	exit 0
fi
