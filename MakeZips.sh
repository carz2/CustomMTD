#!/bin/bash
version=`awk -F \= '/^version=/ { print $2 }' MTDPartPatcher/patchbootimg.sh`
updater=META-INF/com/google/android/updater-script
outdir=../CustomMTD_out/v${version}
if [ ! -e "$outdir" ];
then
	install -d $outdir
fi
signtools=$(dirname $(find $PWD -name signapk.jar|grep -v \.repo))
if [ "$?" != "0" ];
then
	echo "signapk.jar not found, files will not be signed"
	signtools=skip
fi
boot ()
{
cat > $updater << "EOF"
set_progress(1.000000);
EOF
echo "ui_print(\"CustomMTD Patcher v${version}\");" >> $updater
cat >> $updater << "EOF"
ui_print("Boot Mode");
ui_print("Extracting Patch Tools...");
package_extract_dir("MTDPartPatcher", "/tmp");
set_perm(0, 0, 0700, "/tmp/patchbootimg.sh");
set_perm(0, 0, 0700, "/tmp/mkbootimg");
set_perm(0, 0, 0700, "/tmp/unpackbootimg");
run_program("/tmp/patchbootimg.sh", "boot");
ui_print("Custom MTD written");
EOF
zip -r ${outdir}/boot-v${version}-CustomMTD.zip META-INF MTDPartPatcher
sign ${outdir}/boot-v${version}-CustomMTD.zip
return
}
AutoMTD ()
{
tar -cz -f AutoMTD_partitionPatcher/AutoMTDPatchTools/MTDPartPatcher.tar.gz MTDPartPatcher
sed s/version=.*\$/version=${version}/ -i AutoMTD_partitionPatcher/PatchUpdateScript.sh 
tar -cj -f ${outdir}/AutoMTD_partitionPatcher_v${version}.tar.bz2 AutoMTD_partitionPatcher
# make zip for easy forum posting
zip ${outdir}/AutoMTD_partitionPatcher_v${version}.zip ${outdir}/AutoMTD_partitionPatcher_v${version}.tar.bz2
rm AutoMTD_partitionPatcher/AutoMTDPatchTools/MTDPartPatcher.tar.gz
return
}
recovery ()
{
cat > $updater << "EOF"
set_progress(1.000000);
EOF
echo "ui_print(\"CustomMTD Patcher v${version}\");" >> $updater
cat >> $updater << "EOF"
ui_print("Recovery Mode");
ui_print("Extracting Patch Tools...");
package_extract_dir("MTDPartPatcher", "/tmp");
set_perm(0, 0, 0700, "/tmp/patchbootimg.sh");
set_perm(0, 0, 0700, "/tmp/mkbootimg");
set_perm(0, 0, 0700, "/tmp/unpackbootimg");
run_program("/tmp/patchbootimg.sh", "recovery");
ui_print("Custom MTD written");
ui_print("Please wipe system,cache & data");
ui_print("& reboot to recovery for changes");
ui_print("to take effect");
EOF
zip -r ${outdir}/recovery-v${version}-CustomMTD.zip META-INF MTDPartPatcher
sign ${outdir}/recovery-v${version}-CustomMTD.zip
return
}

Test ()
{
cat > $updater << "EOF"
set_progress(1.000000);
EOF
echo "ui_print(\"CustomMTD Patcher v${version}\");" >> $updater
cat >> $updater << "EOF"
ui_print("Test Mode");
ui_print("Extracting Patch Tools...");
package_extract_dir("MTDPartPatcher", "/tmp");
set_perm(0, 0, 0700, "/tmp/patchbootimg.sh");
set_perm(0, 0, 0700, "/tmp/mkbootimg");
set_perm(0, 0, 0700, "/tmp/unpackbootimg");
run_program("/tmp/patchbootimg.sh", "test");
ui_print("Please see /sdcard/<device_CustomMTD.tar.gz");
EOF
zip -r ${outdir}/test-v${version}-CustomMTD.zip META-INF MTDPartPatcher
sign ${outdir}/test-v${version}-CustomMTD.zip
return
}

patchrunparts ()
{
cat > $updater << "EOF"
set_progress(1.000000);
EOF
echo "ui_print(\"CustomMTD Patcher v${version}\");" >> $updater
cat >> $updater << "EOF"
ui_print("Boot Mode with run-parts patch");
ui_print("Extracting Patch Tools...");
package_extract_dir("MTDPartPatcher", "/tmp");
set_perm(0, 0, 0700, "/tmp/patchbootimg.sh");
set_perm(0, 0, 0700, "/tmp/mkbootimg");
set_perm(0, 0, 0700, "/tmp/unpackbootimg");
run_program("/tmp/patchbootimg.sh", "boot", "runparts");
EOF
zip -r ${outdir}/boot-rpp-v${version}-CustomMTD.zip META-INF MTDPartPatcher
sign ${outdir}/boot-rpp-v${version}-CustomMTD.zip
return
}
sign ()
{
if [ "$signtools" = "skip" ];
then
	echo "skipping signing"
	return
fi
for file in $@;do
	ext=zip
	echo "signing ${file}..."
	java -jar ${signtools}/signapk.jar ${signtools}/testkey.x509.pem ${signtools}/testkey.pk8 $file ${outdir}/`basename $file .${ext}`_S.${ext}
	echo "signing ${file} complete"
	rm ${file}
	echo "signed file : ${outdir}/`basename $file .${ext}`_S.${ext}"
done 
return
}
boot
AutoMTD
recovery
#Test
patchrunparts
rm META-INF/com/google/android/updater-script
