#!/bin/dash

# Line discipline helper for systemd
#
# Copyright (C) 2020 Jakub Vanek <linuxtardis@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This package is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

set -e

# sysfs device path from systemd: sys/devices/platform/ev3-ports/ev3-ports:in3/lego-port/port2/ev3-ports:in3:ev3-uart-host
sysfs_device="$1"

# device basename: ev3-ports:in3:ev3-uart-host
base_name="$(basename "$sysfs_device")"

# take only the port: ev3-ports:in3
uart_port="$(echo "$base_name" | grep -o 'ev3-ports:in[1-4]' )"

# launch the line discipline
exec /usr/sbin/ldattach 29 "/dev/tty_$uart_port"
