#!/bin/dash

# USB Gadget for LEGO MINDSTORMS EV3 hardware
#
# Copyright (C) 2015,2017 David Lechner <david@lechnology.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.

set -e

# command line parameters
command="$1" # "up" or "down"
udc_device="$2" # a udc device name, such as "musb-hdrc.1.auto"

g="/sys/kernel/config/usb_gadget/ev3dev"

ev3_usb_up() {
    usb_ver="0x0200" # USB 2.0
    dev_class="2" # Communications - LEGO firmware is 0
    vid="0x0694" # LEGO Group
    pid="0x0005" # EV3
    device="0x3001" # this should be incremented any time there are breaking changes
                    # to this script so that the host OS sees it as a new device and
                    # re-enumerates everything rather than relying on cached values
    mfg="LEGO Group" # matches LEGO firmware
    prod="EV3+ev3dev" # LEGO firmware is just "EV3"
    # Read bluetooth mac address from eeprom - this is what LEGO firmware uses for serial
    # FIXME: hard-coding the sysfs path could be fragile
    serial="$(grep ^BOARD_INFO_SERIAL_NUM= /sys/class/board-info/board0/uevent | cut -d = -f 2)"
    attr="0xC0" # Self powered
    pwr="1" # 2mA
    cfg1="CDC"
    cfg2="RNDIS"
    # add colons for MAC address format
    mac="$(echo ${serial} | sed 's/\(\w\w\)/:\1/g' | cut -b 2-)"
    # Change the first number for each MAC address - the second digit of 2 indicates
    # that these are "locally assigned (b2=1), unicast (b1=0)" addresses. This is
    # so that they don't conflict with any existing vendors. Care should be taken
    # not to change these two bits.
    dev_mac1="02$(echo ${mac} | cut -b 3-)"
    host_mac1="12$(echo ${mac} | cut -b 3-)"
    dev_mac2="22$(echo ${mac} | cut -b 3-)"
    host_mac2="32$(echo ${mac} | cut -b 3-)"
    ms_vendor_code="0xcd" # Microsoft
    ms_qw_sign="MSFT100" # also Microsoft (if you couldn't tell)
    ms_compat_id="RNDIS" # matches Windows RNDIS Drivers
    ms_subcompat_id="5162001" # matches Windows RNDIS 6.0 Driver


    tmpdir=$(mktemp -d)
    mount /dev/mmcblk0p1 $tmpdir
    if [ -f $tmpdir/ev3dev.txt ]; then
        cdc_only=$(grep -i "^cdc_only=\(true\|yes\|1\)" $tmpdir/ev3dev.txt | cut -b 10-)
    fi
    umount $tmpdir

    if [ -d ${g} ]; then
        if [ "$(cat ${g}/UDC)" != "" ]; then
            echo "Gadget is already up."
            exit 1
        fi
        echo "Cleaning up old directory..."
        ev3_usb_down
    fi
    echo "Setting up gadget..."

    # Create a new gadget

    mkdir ${g}
    echo "${usb_ver}" > ${g}/bcdUSB
    echo "${dev_class}" > ${g}/bDeviceClass
    echo "${vid}" > ${g}/idVendor
    echo "${pid}" > ${g}/idProduct
    echo "${device}" > ${g}/bcdDevice
    mkdir ${g}/strings/0x409
    echo "${mfg}" > ${g}/strings/0x409/manufacturer
    echo "${prod}" > ${g}/strings/0x409/product
    echo "${serial}" > ${g}/strings/0x409/serialnumber

    # Create 2 configurations. The first will be CDC. The second will be RNDIS.
    # Thanks to os_desc, Windows should use the second configuration.

    # config 1 is for CDC

    mkdir ${g}/configs/c.1
    echo "${attr}" > ${g}/configs/c.1/bmAttributes
    echo "${pwr}" > ${g}/configs/c.1/MaxPower
    mkdir ${g}/configs/c.1/strings/0x409
    echo "${cfg1}" > ${g}/configs/c.1/strings/0x409/configuration

    # Create the CDC function

    mkdir ${g}/functions/ecm.usb0
    echo "${dev_mac1}" > ${g}/functions/ecm.usb0/dev_addr
    echo "${host_mac1}" > ${g}/functions/ecm.usb0/host_addr

    # config 2 is for RNDIS

    mkdir ${g}/configs/c.2
    echo "${attr}" > ${g}/configs/c.2/bmAttributes
    echo "${pwr}" > ${g}/configs/c.2/MaxPower
    mkdir ${g}/configs/c.2/strings/0x409
    echo "${cfg2}" > ${g}/configs/c.2/strings/0x409/configuration

    # On Windows 7 and later, the RNDIS 5.1 driver would be used by default,
    # but it does not work very well. The RNDIS 6.0 driver works better. In
    # order to get this driver to load automatically, we have to use a
    # Microsoft-specific extension of USB.

    echo "1" > ${g}/os_desc/use
    echo "${ms_vendor_code}" > ${g}/os_desc/b_vendor_code
    echo "${ms_qw_sign}" > ${g}/os_desc/qw_sign

    # Create the RNDIS function, including the Microsoft-specific bits

    mkdir ${g}/functions/rndis.usb0
    echo "${dev_mac2}" > ${g}/functions/rndis.usb0/dev_addr
    echo "${host_mac2}" > ${g}/functions/rndis.usb0/host_addr
    echo "${ms_compat_id}" > ${g}/functions/rndis.usb0/os_desc/interface.rndis/compatible_id
    echo "${ms_subcompat_id}" > ${g}/functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id

    # Link everything up and bind the USB device

    ln -s ${g}/functions/ecm.usb0 ${g}/configs/c.1
    ln -s ${g}/functions/rndis.usb0 ${g}/configs/c.2
    ln -s ${g}/configs/c.2 ${g}/os_desc
    echo "${udc_device}" > ${g}/UDC

    echo "Done."
}

ev3_usb_down() {
    if [ ! -d ${g} ]; then
        echo "Gadget is already down."
        exit 1
    fi
    echo "Taking down gadget..."

    # Have to unlink and remove directories in reverse order.
    # Checks allow to finish takedown after error.

    if [ "$(cat ${g}/UDC)" != "" ]; then
        echo "" > ${g}/UDC
    fi
    rm -f ${g}/os_desc/c.2
    rm -f ${g}/configs/c.2/rndis.usb0
    rm -f ${g}/configs/c.1/ecm.usb0
    [ -d ${g}/functions/ecm.usb0 ] && rmdir ${g}/functions/ecm.usb0
    [ -d ${g}/functions/rndis.usb0 ] && rmdir ${g}/functions/rndis.usb0
    [ -d ${g}/configs/c.2/strings/0x409 ] && rmdir ${g}/configs/c.2/strings/0x409
    [ -d ${g}/configs/c.2 ] && rmdir ${g}/configs/c.2
    [ -d ${g}/configs/c.1/strings/0x409 ] && rmdir ${g}/configs/c.1/strings/0x409
    [ -d ${g}/configs/c.1 ] && rmdir ${g}/configs/c.1
    [ -d ${g}/strings/0x409 ] && rmdir ${g}/strings/0x409
    rmdir ${g}

    echo "Done."
}

case ${command} in

up)
    ev3_usb_up
    ;;
down)
    ev3_usb_down
    ;;
*)
    echo "Usage: ev3-usb.sh up|down <udc_device>"
    exit 1
    ;;
esac
