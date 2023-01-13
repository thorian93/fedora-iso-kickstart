#!/bin/bash
# Author: Yevgeniy Goncharov aka xck, http://sys-adm.in
# Adapted for Fedora by: thorian93 (github.com/thorian93)
# Script to generate kickstart Fedora image

while getopts ":k:o:fp" opt; do
  case $opt in
    k)
      KS_CONFIG="$OPTARG"
      ;;
    o)
      OUTPUT_DIR="$OPTARG"
      ;;
    f)
      read -r -s -p "Provide Full Disk Encryption Passphrase: " FDE_PASS_READ
      FDE_PASS="$(mkpasswd "$FDE_PASS_READ")"
      echo "$FDE_PASS"
      ;;
    p)
      read -r -s -p "Provide User Password:" USER_PASS_READ
      USER_PASS="$(mkpasswd "$USER_PASS_READ")"
      echo "$USER_PASS"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Variables
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

FEDORA_RELEASE="36"
MIRROR="https://download.fedoraproject.org/pub/fedora/linux/releases/$FEDORA_RELEASE/Server/x86_64/iso/"
DOWNLOAD_ISO="Fedora-Server-netinst-x86_64-$FEDORA_RELEASE-1.5.iso"
MOUNT_ISO_FOLDER="/mnt/fedora_custom_iso_mount"
EXTRACT_ISO_FOLDER="/tmp/fedora_custom_iso_extract"
NEW_IMAGE_NAME="fedora-$FEDORA_RELEASE-custom"

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
CLS='\033[0m'

# Determine OS

if [ -f /etc/debian_version ]; then
	OS="debian"
	ISOPACKAGE="genisoimage"
	echo "We are running on $OS"
  sudo apt install $ISOPACKAGE -y
elif [ -f /etc/fedora-release ]; then
	OS="fedora"
	ISOPACKAGE="genisoimage"
	echo "We are running on $OS"
  sudo dnf install $ISOPACKAGE -y
else
	echo "This OS no supported by this script. Sorry. Supported distro: Debian, Fedora"
	exit 1
fi

# Functions

_download_image()
{
  echo -e "${GREEN}Get ISO image from mirror - $MIRROR${CLS}"
  if [ ! -d "$SCRIPT_PATH/images" ]; then
  mkdir "$SCRIPT_PATH/images"
  echo -e "${GREEN}Download image - $DOWNLOAD_ISO${CLS}"
  wget $MIRROR$DOWNLOAD_ISO -P "$SCRIPT_PATH/images"
  else
    if [ ! -f "$SCRIPT_PATH/images/$DOWNLOAD_ISO" ]; then
      # If file not exist
      echo -e "${GREEN}Download image - $DOWNLOAD_ISO${CLS}"
      wget $MIRROR$DOWNLOAD_ISO -P "$SCRIPT_PATH/images"
    else
      echo -e "${GREEN}File already downloaded${CLS}"
    fi
  fi
}

_mount() {
  if [ ! -d $MOUNT_ISO_FOLDER ]; then
    sudo mkdir $MOUNT_ISO_FOLDER
  fi

  if [ ! -d $EXTRACT_ISO_FOLDER ]; then
    sudo mkdir $EXTRACT_ISO_FOLDER
  fi
  sudo mount "$SCRIPT_PATH/images/$DOWNLOAD_ISO" $MOUNT_ISO_FOLDER
}

_prepare_iso() {
  sudo cp -rp $MOUNT_ISO_FOLDER/* $EXTRACT_ISO_FOLDER
  sudo cp "$KS_CONFIG" "$EXTRACT_ISO_FOLDER/ks.cfg"
  if [ -n "$FDE_PASS" ]; then
    sudo sed -i "s/\$fdepass/$FDE_PASS/" "$EXTRACT_ISO_FOLDER/ks.cfg"
  else
    sudo sed -i 's/--encrypted --luks-version=luks1 $fdepass//' "$EXTRACT_ISO_FOLDER/ks.cfg"
  fi
  if [ -n "$USER_PASS" ]; then
    sudo sed -i "s/password=\$userpass --iscrypted/password=$USER_PASS --iscrypted/" "$EXTRACT_ISO_FOLDER/ks.cfg"
  else
    sudo sed -i 's/password=$userpass --iscrypted/password=robin/' "$EXTRACT_ISO_FOLDER/ks.cfg"
  fi
  sudo sed -i '/menu default/d' $EXTRACT_ISO_FOLDER/isolinux/isolinux.cfg
  sudo sed -i '/label check/i \
  label auto \
    menu label ^Auto install Fedora Linux \
    kernel vmlinuz \
    menu default \
    append initrd=initrd.img inst.ks=cdrom:/dev/cdrom:/ks.cfg \
    # end' $EXTRACT_ISO_FOLDER/isolinux/isolinux.cfg
}

_generate_iso() {
  echo -e "${GREEN}Generate iso${CLS}"
  sudo $ISOPACKAGE -o "$SCRIPT_PATH/images/$NEW_IMAGE_NAME.iso" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -V "$NEW_IMAGE_NAME" -boot-load-size 4 -boot-info-table -R -J -v -T $EXTRACT_ISO_FOLDER  # -e images/efiboot.img
}

_finish() {
  echo -e "${GREEN}Umount $MOUNT_ISO_FOLDER${CLS}"
  sudo umount $MOUNT_ISO_FOLDER
  if [ -n "$OUTPUT_DIR" ]; then
    mv "$SCRIPT_PATH/images/$NEW_IMAGE_NAME.iso" "$OUTPUT_DIR/$NEW_IMAGE_NAME.iso"
  fi
}

# Main
echo
_download_image
_mount
_prepare_iso
_generate_iso
_finish
echo -e "${RED}Done!${CLS} ${GREEN}New autoimage destination - $SCRIPT_PATH/images/$NEW_IMAGE_NAME.iso${CLS}"
exit 0
