#!/bin/bash
#root@cl-3.3.0-33:/home/partimag/checksum.log$ umount /mnt
#root@cl-3.3.0-33:/home/partimag/checksum.log$ mount /dev/vda1 /mnt
#root@cl-3.3.0-33:/home/partimag/checksum.log$ md5sum -c ./vda1files.md5 > testX.log
#root@cl-3.3.0-33:/home/partimag/checksum.log$ umount /mnt
#root@cl-3.3.0-33:/home/partimag/checksum.log$ ls
#2025-11-27-06-img-check.log  default.log  testX.log  vda1files.md5
#root@cl-3.3.0-33:/home/partimag/checksum.log$ vi valid.sh^C
#root@cl-3.3.0-33:/home/partimag/checksum.log$ pwd
#/home/partimag/checksum.log

pushd /home/partimag/checksum.log
umount /mnt
mount /dev/vda1 /mnt
md5sum -c ./vda1files.md5 > testX.log
umount /mnt
cat testX.log | grep FAIL
popd
