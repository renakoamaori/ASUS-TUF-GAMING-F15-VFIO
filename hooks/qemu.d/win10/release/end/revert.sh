#!/bin/bash
# RUTA: /etc/libvirt/hooks/qemu.d/win10/release/end/revert.sh
source "/etc/libvirt/hooks/qemu.d/win10/vm-vars.conf"

# 1. Restaurar CPUs
systemctl set-property --runtime -- user.slice AllowedCPUs=$SYS_TOTAL_CPUS
systemctl set-property --runtime -- system.slice AllowedCPUs=$SYS_TOTAL_CPUS
systemctl set-property --runtime -- init.scope AllowedCPUs=$SYS_TOTAL_CPUS

# 2. Restaurar energía
echo $VM_OFF_GOVERNOR | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
