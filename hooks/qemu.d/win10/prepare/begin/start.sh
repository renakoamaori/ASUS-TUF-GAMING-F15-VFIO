#!/bin/bash
# RUTA: /etc/libvirt/hooks/qemu.d/win10/prepare/begin/start.sh
source "/etc/libvirt/hooks/qemu.d/win10/vm-vars.conf"

# 1. Optimización de Memoria
echo 3 > /proc/sys/vm/drop_caches
echo 1 > /proc/sys/vm/compact_memory

# 2. CPU Pinning
systemctl set-property --runtime -- user.slice AllowedCPUs=$SYS_TOTAL_CPUS
systemctl set-property --runtime -- system.slice AllowedCPUs=$SYS_TOTAL_CPUS
systemctl set-property --runtime -- init.scope AllowedCPUs=$SYS_TOTAL_CPUS

# 3. Gobernador Performance
echo $VM_ON_GOVERNOR | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
