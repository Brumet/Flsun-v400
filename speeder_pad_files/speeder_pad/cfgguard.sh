#! /bin/bash

# Start Boot Logo
for((j=1;j<=2;j++))
do
for((i=1;i<=19;i++))
        do
        cat /root/$i.raw > /dev/fb0
        sleep 0.1s
done
done
cat /root/20.raw > /dev/fb0

# Start Network
ifconfig wlan0 up
wpa_supplicant -B -D nl80211 -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
sudo chgrp -R pi /run/wpa_supplicant/
sudo chown -R pi /run/wpa_supplicant/
sudo wpa_cli -i wlan0 scan
sudo wpa_cli -i wlan0 scan_result
dhclient wlan0

# USB-DISK update.bin
if [ -f /home/pi/gcode_files/USB-Disk/update.sh ];
then
        echo "USB-DISK start update"
        sudo bash /home/pi/gcode_files/USB-Disk/update.sh
        echo "USB-DISK update end"
else
        echo "USB-DISK the file exist"
fi
