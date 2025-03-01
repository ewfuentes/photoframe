
#! /usr/bin/sh

set -euxo pipefail

CWD=`pwd`

KERNELVER=6.6.47-piCore-v7
TMPDIR=/tmp/`uuidgen`
IMGFILE="piCore-15.0.0.img"

mkdir -p ${TMPDIR}
cd ${TMPDIR}

if [ ! -e ${IMGFILE} ]; then
	wget http://tinycorelinux.net/15.x/armhf/releases/RPi/piCore-15.0.0.zip
	unzip piCore-15.0.0.zip
	truncate -s +200M ${IMGFILE} 
fi

# Download the required tcz packages
if [ ! -e ${TMPDIR}/tce-get ]; then
	git clone https://github.com/JordanHiggins/TceDownload.git
	go build -o tce-get TceDownload/TceDownload.go
fi

# Mount the devices
LOOPDEV=`sudo losetup --show -Pf ${IMGFILE}`
sudo udevadm settle

MNTDIR=${TMPDIR}/image
BOOTDIR=${MNTDIR}/boot
MAINDIR=${MNTDIR}/main
mkdir -p ${BOOTDIR}
mkdir -p ${MAINDIR}

MAINPARTITION=${LOOPDEV}p2
MAIN_SIZE=`lsblk -n --output size --bytes ${MAINPARTITION}`

echo "Main size: ${MAIN_SIZE}" 

if ((${MAIN_SIZE} > (1<<24))); then
	echo "greater!"
else
	echo "Detecting partition start..."
	PART_START=$(sudo fdisk -l "${IMGFILE}" | awk '/^.*img2/ {print $2}')
	SECTOR_SIZE=$(sudo fdisk -l "${IMGFILE}" | awk '/Sector size/ {print $4}')

	echo "Resizing partition 2..."
	echo -e "d\n2\nn\np\n2\n$PART_START\n\nw" | sudo fdisk "$IMGFILE"

	echo "Detaching and reattaching loop device..."
	sudo losetup -d "$LOOPDEV"
	LOOPDEV=$(sudo losetup -Pf --show "$IMGFILE")

	echo "Resizing the filesystem..."
	sudo e2fsck -f -y "${LOOPDEV}p2" || [ $? -eq 1 ]

	sudo resize2fs "${LOOPDEV}p2"

fi

sudo mount -o uid=1000,gid=1000,umask=0022 ${LOOPDEV}p1 ${BOOTDIR}
sudo mount ${LOOPDEV}p2 ${MAINDIR}
sudo udevadm settle

./tce-get -version 15.x -kernel ${KERNELVER} -arch armhf -out tce \
	wifi firmware-rpi-wifi firmware-rpi-bt iproute2 rsync compiletc
sudo chmod g+w tce/*
sudo chown 1001:staff tce/*
sudo cp -a tce/* ${MAINDIR}/tce/optional/
echo "wifi.tcz" | sudo tee -a ${MAINDIR}/tce/onboot.lst
echo "firmware-rpi-wifi.tcz" | sudo tee -a ${MAINDIR}/tce/onboot.lst
echo "firmware-rpi-bt.tcz" | sudo tee -a ${MAINDIR}/tce/onboot.lst
echo "iproute2.tcz" | sudo tee -a ${MAINDIR}/tce/onboot.lst
echo "rsync.tcz" | sudo tee -a ${MAINDIR}/tce/onboot.lst
echo "compiletc.tcz" | sudo tee -a ${MAINDIR}/tce/onboot.lst

mkdir -p mydata
sudo tar -xpf ${MAINDIR}/tce/mydata.tgz -C mydata

cat <<EOF | sudo tee -a mydata/opt/bootlocal.sh > /dev/null
/opt/wifi_connect.sh &
while true; do
	iwconfig
	ip addr
	sleep 5
done
EOF

cat <<EOF | sudo tee mydata/opt/wifi_connect.sh > /dev/null
#! /bin/sh
ifconfig wlan0 up
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant-wlan0.conf
udhcpc -i wlan0
EOF
sudo chmod +x mydata/opt/wifi_connect.sh
sudo chown root:staff mydata/opt/wifi_connect.sh

wpa_passphrase "The Medium Place" | sudo tee mydata/etc/wpa_supplicant-wlan0.conf > /dev/null

sed -i -e "s/$/ brcmfmac.feature_disable=0x82000/" ${BOOTDIR}/cmdline.txt

cat <<EOF | sudo tee -a ${BOOTDIR}/config.txt > /dev/null
dtoverlay=miniuart-bt
EOF

sudo tar -czpf mydata.tgz -C mydata .
sudo chown 1001:staff mydata.tgz
sudo cp mydata.tgz ${MAINDIR}/tce/

sudo umount ${MNTDIR}/*
sudo udevadm settle

sudo losetup -d ${LOOPDEV}
cp ${IMGFILE} ${CWD}
cd ${CWD}
