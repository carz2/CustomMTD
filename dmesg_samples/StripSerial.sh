#!/bin/sh
for i in `echo $@|sed s/$0//`;do
		echo "striping serial from $i"
		sed s/serialno=.*\ a/serialno=XXXXXXXXXX\ a/g -i $i
done
