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
makezip ()
{
cat > $updater << "EOF"
set_progress(1.000000);
EOF
echo "ui_print(\"CustomMTD Patcher v${version}\");" >> $updater
echo "ui_print(\"Mode=$1\");" >> $updater
cat >> $updater << "EOF"
ui_print("Extracting Patch Tools...");
package_extract_dir("MTDPartPatcher", "/tmp");
set_perm(0, 0, 0700, "/tmp/patchbootimg.sh");
set_perm(0, 0, 0700, "/tmp/mkbootimg");
set_perm(0, 0, 0700, "/tmp/unpackbootimg");
EOF
echo "run_program(\"/tmp/patchbootimg.sh\", \"$1\");" >> $updater
cat >> $updater << "EOF"
if file_getprop("/tmp/cMTD.log","success") == "true"
then
    ui_print("Custom MTD written");
    if file_getprop("/tmp/cMTD.log","Mode") != "boot"
    then
        ui_print("Previous Partition sizes");
        ui_print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        ui_print(file_getprop("/tmp/cMTD.log","Orig_systemSize"));
        ui_print(file_getprop("/tmp/cMTD.log","Orig_cacheSize"));
        ui_print(file_getprop("/tmp/cMTD.log","Orig_dataSize"));
        ui_print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    endif;
    if file_getprop("/tmp/cMTD.log","Mode") != "remove"
    then
        ui_print("New Partition sizes");
        ui_print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        ui_print(file_getprop("/tmp/cMTD.log","New_systemSize"));
        ui_print(file_getprop("/tmp/cMTD.log","New_cacheSize"));
        ui_print(file_getprop("/tmp/cMTD.log","New_dataSize"));
        ui_print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        if file_getprop("/tmp/cMTD.log","Mode") == "recovery" &&
           ( file_getprop("/tmp/cMTD.log","Orig_systemSize") != file_getprop("/tmp/cMTD.log","New_systemSize") ||
             file_getprop("/tmp/cMTD.log","Orig_cacheSize") != file_getprop("/tmp/cMTD.log","New_cacheSize") ||
             file_getprop("/tmp/cMTD.log","Orig_dataSize") != file_getprop("/tmp/cMTD.log","New_dataSize")
           )
        then
           ui_print("Please format:");
           ui_print("system,cache and data");
           ui_print("and reboot to recovery");
           ui_print("before 'flash' or 'restore'");
        else
           ui_print("recovery's partitions have not");
           ui_print("been changed");
           ui_print("format not required");
        endif;
    else
        ui_print("customMTD removed");
        ui_print("Please format:");
        ui_print("system,cache and data");
        ui_print("and reboot to recovery");
        ui_print("before 'flash' or 'restore'");
    endif;
else
    ui_print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    ui_print("############ ERROR #############");
    ui_print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    if file_getprop("/tmp/cMTD.log","Error1") != ""
    then
        ui_print(file_getprop("/tmp/cMTD.log","Error1"));
    endif;
    if file_getprop("/tmp/cMTD.log","Error2") != ""
    then
        ui_print(file_getprop("/tmp/cMTD.log","Error2"));
    endif;
    if file_getprop("/tmp/cMTD.log","Error3") != ""
    then
        ui_print(file_getprop("/tmp/cMTD.log","Error3"));
    endif;
    ui_print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
endif;
if file_getprop("/tmp/cMTD.log","Mode") == "testrun"
then
    ui_print("Test Mode complete, see ");
    ui_print("/sdcard/cMTD-testoutput.txt");
    ui_print("for full output");
endif;
EOF
zip -r ${outdir}/$1-v${version}-CustomMTD.zip META-INF MTDPartPatcher
sign ${outdir}/$1-v${version}-CustomMTD.zip
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
AutoMTD
for output in recovery boot remove test;do
    makezip $output
done
rm $updater
