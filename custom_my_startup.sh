#!/bin/sh

# don't disable serial console :)
sed -i "s#/usr/sbin/consolesecurity#/bin/uname#" /etc/scripts/docsis.pcd

# OG modem stuff, without this, system doesn't do anything
/etc/scripts/sys_startup.sh -g8

# if OG modem stuff doesn't run, run the watchdog so the system doesn't reboot
#watchdog_rt -t 1 /dev/watchdog

# change the root password to root
echo -e "root\nroot" | passwd root

# override the custom dropbear that the modem bundles with one that
# drops directly into the shell
mount -o "bind" /nvram/dropbear /usr/sbin/dropbear

# run a dropbear client on port 6666
dropbear -r /etc/rsa_key.priv -E -p 6666 -a
