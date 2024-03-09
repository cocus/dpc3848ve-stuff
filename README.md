# DPC3848VE jailbreak and hacking
This is just me tinkering with this modem, trying to make it useful, as a fully fledged Wireless AP (in bridge mode, like what Ubiquiti's NanoStations), or Wireless client, and/or NAS.
I've already contacted Technicolor's (now Vantiva) open source department to ask for the sources used on this modem, but no reply as of yet.

# How to access the modem
I'm currently using the serial header exposed on the motherboard to get a console on both ATOM and ARM cores. Sadly, the ARM side disables the console after a short while as part of its boot sequence. However, it's possibly to skip this behavior by simply not running the main app.
Both ATOM and ARM serial terminals run at the same voltage (3.3V), have the same pinout (RX, TX, GND, VCC), and use the same baudrate (115200bps, 8, N, 1).

## ARM Core
In order to jailbreak the ARM core, you need to power the modem up with the console attached to the ARM header. Once you see the kernel starting up, start hitting enter to enable the busybox console; until you see a "#". At this time, we need to modify a single file to disable the standard boot sequence. Paste (without worrying for the text being overwritten by log messages) the following:

```
mv /nvram/my_startup.sh /nvram/my_startup.bkp && echo -e "#!/bin/sh\nwatchdog_rt -t 1 /dev/watchdog" > /nvram/my_startup.sh && chmod +x /nvram/my_startup.sh && reboot
```

This, in theory, should rename the `my_startup.sh` file on the `/nvram` to `my_startup.bkp`, then create a new script that only calls `watchdog_rt` (so the system's watchdog doesn't reboot the core constantly), mark it as executable and reboot.
After it reboots, you'll see that you can access the console and nothing is spewing log messages as before. The main application didn't start, but the system is alive.
At this stage, we need to modify the `my_startup.sh` file again, so the original application doesn't block the serial console after booting, and we lay the foundation to spawn a patched dropbear ssh server in the future.
Using `vi`, edit the file, clear it completely and use the following contents:
```
#!/bin/sh

# don't disable serial console :)
sed -i "s#/usr/sbin/consolesecurity#/bin/uname#" /etc/scripts/docsis.pcd

# OG modem stuff, without this, system doesn't do anything
/etc/scripts/sys_startup.sh -g8

# if OG modem stuff doesn't run, run the watchdog so the system doesn't reboot
#watchdog_rt -t 1 /dev/watchdog

# change the root password to root
echo -e "root\nroot" | passwd root

# run a dropbear client on port 6666, if the file exists
[ -f /nvram/dropbear ] && /nvram/dropbear -r /etc/rsa_key.priv -E -p 6666 -a
```

At this point, we should reboot the modem once again. This time, let the modem finish booting. You'll see that this time you can still access the console!

Taking advantage of this, we can start a ssh server right away. However, the bundled dropbear server ALWAYS start a custom and proprietary CLI ("/usr/sbin/cli"). We don't want that, we want a shell. So, in order to fix this, it's possible to get the bundled dropbear binary, by uploading it to a tftp server (since no ssh, scp, ftp, etc is available), then patching it so it starts "/bin/sh" after logon.
Not only that, but there's a nasty addition to the program, where it passes multiple arguments to the shell, namely "-l", "-hostEntity" and the remote IP. In order to fix this, I just patched a single assembly line, which instead of loading the pointer of the string literal "-l", it loads a null value; effectively voiding the rest of the arguments passed to the process.
If you want, take the `dropbear_patched` binary from this repo, place it on a tftp or web server, and use tftp or wget to downlod it. Place the file in `/nvram/dropbear`, and mark it as execcutable with `chmod +x /nvram/dropbear`.
At this point, you can reboot once more, and after the modem finishes booting, you'll have a new ssh server running at port `6666`.

> NOTE: You might encounter some issues with the ciphers and the key exchange algorithms, so use something like: `ssh -oCiphers=aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc -oKexAlgorithms=+diffie-hellman-group1-sha1  -p6666 root@192.168.0.1`

## ATOM Core
It already provides a root shell on the serial console. No dropbear or sshd on the image, but telnetd is present.

To run the telnetd server on boot, just run the following:
```
mkdir -p /nvram/sdk && touch /nvram/sdk/docsis_relax
```
This just disables the verification done on many init scripts for "docsis compliance", which telnetd is one of them.

Usually the IP of the ATOM core is the .254 on the same subnet as the ARM core, for instance `192.168.0.254` (while the "modem/ARM" IP is `192.168.0.1`). Check the `br0` interface for its IP.

TODO: Investigate where to grab a statically linked sshd, busybox, etc.

## Partitions
For some god unknown reason, the eMMC is "shared" between the ATOM and ARM cores.


| Partition                | Start sector | End sector | Size (kb) | Purpose | Mount point |
| ------------------------ | ------------ | ---------- | --------- | ------------ | ----------- |
|                          |   4096       |    4343    |    128    | APPCPU SIGNATURE #1 | ? |
|                          |   4344       |    4351    |     64    | APPCPU AID #1 | ? |
|                          |   4352       |    4599    |    128    | APPCPU SIGNATURE #2 | ? |
|                          |   4600       |    4607    |     64    | APPCPU AID #1 | ? |
| /dev/mmcblk0p1           |   4608       |   12799    |   4096    | APPCPU KERNEL #1 | ? |
| /dev/mmcblk0p2           |  12800       |   20991    |   4096    | APPCPU KERNEL #2 | ? |
| /dev/mmcblk0p3           |  20992       |   55807    |  17408    | APPCPU ROOTFS #1 (squashfs, ro, rootfs for ATOM) | / (ATOM) |
| /dev/mmcblk0p4           |  55808       |  230143    |  87168    | Extended part? | ? |
| /dev/mmcblk0p5           |  56064       |   90879    |  17408    | APPCPU ROOTFS #2 (squashfs, ro, rootfs for ATOM) | ? |
| /dev/mmcblk0p6           |  91136       |   95231    |   2048    | APPCPU NVRAM #1 (ext3, rw) | /nvram (ATOM) |
| /dev/mmcblk0p7           |  95488       |   99583    |   2048    | APPCPU NVRAM #2 | ? |
|                          |  99584       |  100095    |    512    | NPCPU UBOOT | ? |
|                          | 100096       |  100607    |    256    | NPCPU UBOOT ENV #1 | ? |
| /dev/mmcblk0p8           | 100608       |  106751    |   3072    | NPCPU KERNEL #1 | ? |
| /dev/mmcblk0p9           | 107008       |  113151    |   3072    | NPCPU KERNEL #2 | ? |
| /dev/mmcblk0p10          | 113408       |  117503    |   2048    | NPCPU NVRAM #1 (ext3, rw) | /nvram (ARM) |
| /dev/mmcblk0p11          | 117760       |  121855    |   2048    | NPCPU NVRAM #2 (ext3, rw) | /nvram2 (ARM) |
| /dev/mmcblk0p12          | 122112       |  140543    |   9216    | NPCPU ROOTFS #1, squashfs, ro, rootfs #1 for ARM | / (ARM) |
| /dev/mmcblk0p13          | 140800       |  159231    |   9216    | NPCPU ROOTFS #2, squashfs, ro, rootfs #2 for ARM | ? |
| /dev/mmcblk0p14          | 159488       |  188159    |  14336    | NPCPU GWFS #1 (squashfs, ro, webpages, binary utils) | /fss/gw (ARM) |
| /dev/mmcblk0p15          | 188416       |  217087    |  14336    | NPCPU GWFS #1 (squashfs, ro, webpages, binary utils) | ? |

## Default "IntelCE" boot (ATOM)
```
shell> ord4 0xdf9fa004 0xB (write 0x0000000b to 0xdf9fa004)
shell> ord4 0xC80D0000 0x03000000 (write 0x03000000 to 0xC80D0000)
shell> load -m 0x200000 -i a -t emmc (load from emmc, from the active image, to memory address 0x200000)
get Active Image info success:240000, 400000, 1, 1, 3
eMMC kernel command:  root=/dev/mmcblk0p3
Load data from emmc
Load done.
shell> bootkernel -b 0x200000 "console=ttyS0,115200 ip=static memmap=exactmap memmap=128K@128K memmap=240M@1M" (boots a kernel from memory address 0x200000 with the given argument)
Working Cmd: console=ttyS0,115200 ip=static memmap=exactmap memmap=128K@128K memmap=240M@1M root=/dev/mmcblk0p3
```

As a side note, while on this IntelCE "BIOS" shell, I wasn't able to make use of the tftp commands, neither the ping, because even setting the IP address as static, I couldn't access my machine (neither my machine could ping the modem).


## Default u-boot environment (ARM)

    bootcmd=while itest.b 1 == 1;do;if itest.b ${ACTIMAGE} == 1 || itest.b ${ACTIMAGE} == 3;then aimgname=UBFI1; aubfiaddr=${UBFIADDR1};bimgname=UBFI2; bubfiaddr=${UBFIADDR2}; bimgnum=2;else if itest.b ${ACTIMAGE} == 2;then aimgname=UBFI2; aubfiaddr=${UBFIADDR2};bimgname=UBFI1; bubfiaddr=${UBFIADDR1}; bimgnum=1;else echo *** ACTIMAGE invalid; exit;fi;fi;if itest.b ${ACTIMAGE} == 3;then eval ${rambase} + ${ramoffset};eval ${RAM_IMAGE_OFFSET} + ${evalval};set UBFIADDR3 ${evalval};if autoscr ${evalval};then bootm ${LOADADDR};else echo Reloading RAM image;tftpboot ${ramimgaddr} ${UBFINAME3};if autoscr ${ramimgaddr};then bootm ${LOADADDR};else setenv ACTIMAGE 1;fi;fi;fi; echo *** ACTIMAGE = ${ACTIMAGE}, will try to boot $aimgname stored @${aubfiaddr};if autoscr $aubfiaddr;then echo *** $aimgname bootscript executed successfully.;echo Start booting...;bootm ${LOADADDR};fi;echo *** $aimgname is corrupted, try $bimgname...;setenv ACTIMAGE $bimgnum;if autoscr $bubfiaddr;then echo *** $bimgname bootscript executed successfully.;echo Check image...;if imi ${LOADADDR};then echo Save updated ACTIMAGE...;saveenv;echo Image OK, start booting...;bootm ${LOADADDR};fi;fi;echo Backup image also corrupted...exit.;exit;done;
    bootdelay=2
    baudrate=115200
    ipaddr=192.168.100.1
    serverip=192.168.100.2
    gatewayip=192.168.100.2
    netmask=255.255.255.0
    LOADADDR=0
    RAM_IMAGE_OFFSET=0x03C00000
    RAM_IMAGE_SIZE=0x00400000
    BOOTPARAMS_AUTOUPDATE=on
    BOOTPARAMS_AUTOPRINT=off
    erase_spi_env=eval ${flashbase} + ${envoffset1} && protect off ${evalval} +${envsize} && erase ${evalval} +${envsize} && protect on ${evalval} +${envsize} && eval ${flashbase} + ${envoffset2} && protect off ${evalval} +${envsize} && erase ${evalval} +${envsize} && protect on ${evalval} +${envsize}
    erase_mmc_env=eval ${rambase} + ${ramoffset} && bufferbase=${evalval} &&mmcaddr2blk $envoffset1 && envblkaddr=$blocksize && mmcaddr2blk $envsize && envblksize=$blocksize && mw ${bufferbase} 0xFF $envsize &&mmc write ${bufferbase} $envblkaddr $envblksize
    erase_env=if itest.s ${bootdevice} == mmc; then run erase_mmc_env;else run erase_spi_env;fi;echo Please reset the board to get default env.
    board_revision=0x00000000
    serialconsole=enable
    flashbase=0x08000000
    rambase=0x40000000
    boardtype=0x00000002
    bootmode=0x00000001
    ramoffset=0x10000000
    ramsize=0x10000000
    aid1offset=0x0021F000
    aid2offset=0x0023F000
    ubootoffset=0x030A0000
    ubootsize=0x00040000
    envoffset1=0x030E0000
    envoffset2=0x030E0000
    envsize=0x00020000
    arm11ubfioffset1=0x00000000
    arm11ubfisize1=0x00000000
    arm11ubfioffset2=0x00000000
    arm11ubfisize2=0x00000000
    atomubfioffset1=0x00000000
    atomubfisize1=0x00000000
    atomubfioffset2=0x00000000
    atomubfisize2=0x00000000
    arm11nvramoffset=0x00000000
    arm11nvramsize=0x00000000
    silicon_stepping=0x0000000C
    signature1_offset=0x00200000
    signature2_offset=0x00220000
    signature_size=0x00020000
    signature_number=0x00000020
    emmc_flash_size=0x00000070
    mmc_part_arm11_kernel_0=8
    mmc_part_arm11_kernel_1=9
    mmc_part_arm11_rootfs_0=12
    mmc_part_arm11_rootfs_1=13
    mmc_part_arm11_gw_fs_0=14
    mmc_part_arm11_gw_fs_1=15
    mmc_part_arm11_nvram=10
    mmc_part_arm11_nvram_2=11
    mmc_part_atom_kernel_0=1
    mmc_part_atom_kernel_1=2
    mmc_part_atom_rootfs_0=3
    mmc_part_atom_rootfs_1=5
    cefdk_s1_offset=0x00080800
    cefdk_s1_size=0x00010000
    cefdk_s2_offset=0x00090800
    cefdk_s2_size=0x00009400
    cefdk_s3_offset=0x00099C00
    cefdk_s3_size=0x00065400
    cefdk_s1h_offset=0x000FF800
    cefdk_s1h_size=0x00000800
    cefdk_s2h_offset=0x00100000
    cefdk_s2h_size=0x00000800
    cefdk_s3h_offset=0x000FF000
    cefdk_s3h_size=0x00000800
    verify=n
    bootdevice=mmc
    UBFIADDR1=0x03120000
    UBFIADDR2=0x03440000
    cefdk_version=0x00054C4B
    aep_mode=0x00000001
    ver=U-Boot 1.2.0-dirty (May 10 2016 - 11:29:11) Cisco-Boot 3.4.22.5
    l2switch_internal_mac_address=00.50.f1.12.b2.72
    stdin=serial
    stdout=serial
    stderr=serial
    active_aid=2
    aididx_app_kernel=0
    aididx_app_root_fs=0
    aididx_app_vgw_fs=0
    aididx_np_kernel=0
    aididx_np_root_fs=0
    aididx_np_gw_fs=0
    aididx_rsvd_6=0
    aididx_rsvd_7=0
    aididx_rsvd_8=0
    aididx_rsvd_9=0
    aididx_rsvd_10=0
    aididx_rsvd_11=0
    aididx_rsvd_12=0
    aididx_rsvd_13=0
    aididx_rsvd_14=0
    aididx_rsvd_15=0
    actimage_atom_kernel=1
    actimage_atom_rootfs=1
    actimage_atom_vgfs=1
    actimage_arm_kernel=1
    actimage_arm_rootfs=1
    actimage_arm_gwfs=1
    ACTIMAGE=1
    consolesecurity=disable


# Build of Images
## ATOM Core Linux
> NOTE: this is just the kernel, and it's a WIP.

### Building the kernel
Using [this firmware](https://osp.avm.de/fritzbox/fritzbox-6490-cable/source-files-FRITZ.Box_6490_Cable-x86-07.29.tar.gz "this firmware") for another device, and using the attached .config file, I was able to build a basic toolchain that lets the kernel be built. In theory, what I did was:
```
mkdir intelpuma
cd intelpuma
wget https://osp.avm.de/fritzbox/fritzbox-6490-cable/source-files-FRITZ.Box_6490_Cable-x86-07.29.tar.gz
tar xf source-files-FRITZ.Box_6490_Cable-x86-07.29.tar.gz
cd host-sources
tar xf buildroot-2018.11.4.tar.bz2
cd buildroot-2018.11.4
cp ../../conf/buildroot.config.x86 .config
sed -i 's#BR2_DEFCONFIG="/DOES/NOT/EXIST"#BR2_DEFCONFIG="$(BASE_DIR)/"#' .config
sed -i 's#BR2_DL_DIR="/DOES/NOT/EXIST"#BR2_DL_DIR="$(BASE_DIR)/downloads"#' .config
mkdir -p downloads
# enter menuconfig, don't change anything, just save and exit
make menuconfig
# now build theh toolchain
make toolchain
# stop it when it starts downloading the linux sources!

cd ../../

# run this once!
export PATH=$PATH:$(pwd)/host-sources/buildroot-2018.11.4/output/host/bin

cd sources/kernel/linux
# copy the tweaked.config file here as .config
# also copy the kernel.patch as kernel.patch

# apply the patches (or use git apply)
patch < kernel.patch

# edit .config and disable AVM_PROM

# build kernel
make -j $(nproc)

# resulting image will be at arch/x86/boot/bzImage
```

This source doesn't seem to correlate to the same product as this modem, so I had to severely cripple the "cablemodem" functionality (specially EVERYTHING related to AVM).
Remember that this is a WIP!.

#### Issues related to newer compilers and python
Fix for newer compilers on lexer files: https://github.com/BPI-SINOVOIP/BPI-M4-bsp/issues/4#issuecomment-1296184876
Fix for newer compilers and gcc's reload1.c: edit the file with the error, move the condition after the && to another #ifdef and add a new #endif right below the nearest #endif.
Fix for newer python: Use the diffconfig file from this repo, and replace it on `scripts/diffconfig`.

### Loading the kernel through ymodem
Since I can't make the tftp work on the "IntelCE" shell/BIOS, the only non-destructive way of testing images is to load them through ymodem. Yes, it's slow, but I don't know how to change the baudrate from the shell (yet).
I'll use `minicom` because it's easy to send stuff through ymodem. Power off the modem, connect your serial adapter to the "ATOM" header, then run:
```
# start minicom
minicom -D /dev/ttyUSB0 -b 115200

# at this moment, turn on the modem, and start hitting the ENTER key until you see "shell>"

ord4 0xdf9fa004 0xB
ord4 0xC80D0000 0x03000000
ymodem 0x200000

# at this moment, use minicom to send the bzImage built on the previous step. use CTRL+A, S and select ymodem. to select the file, navigate and use the spacebar to select and enter to send.

# when it finishes, return to the shell prompt and boot the system!
bootkernel -b 0x200000 "console=ttyS0,115200 ip=static memmap=exactmap memmap=128K@128K memmap=240M@1M root=/dev/mmcblk0p3"
```

## ARM Core Linux
TODO! (although I kinda don't think it's required if you want to use the modem as a Wireless AP/Station/NAS).

# Sites of interest
* Sources? https://boxmatrix.info/wiki/Property:Puma6
* Sources? https://sourceforge.net/projects/dg3270.arris/files/DG3270_9.1.103FB/
* Exploit to gain root on the ARM core: https://github.com/Ostoic/dpcpwn
