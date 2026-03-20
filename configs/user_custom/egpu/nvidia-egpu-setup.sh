#!/bin/bash

# Step 1: Find any Thunderbolt peripheral (eGPU enclosure)
EGPU_UUID=$(boltctl list 2>/dev/null | grep -B1 "type:.*peripheral" | grep -oP '[a-f0-9-]{36}' | head -1)

if [ -z "$EGPU_UUID" ]; then
    echo "No Thunderbolt eGPU enclosure detected, skipping"
    exit 0
fi

DEVICE_NAME=$(boltctl info "$EGPU_UUID" 2>/dev/null | grep -oP '(?<=name:\s{8})\S.*' || echo "unknown")
echo "eGPU enclosure found: $DEVICE_NAME (UUID: $EGPU_UUID)"

STATUS=$(boltctl info "$EGPU_UUID" 2>/dev/null | grep -oP '(?<=status:\s{8})\S+')
echo "Status: $STATUS"

# Step 2: Enroll if not stored (auto-authorize on future connects)
STORED=$(boltctl info "$EGPU_UUID" 2>/dev/null | grep "stored:")
if echo "$STORED" | grep -q "no"; then
    echo "eGPU not enrolled, enrolling with auto policy..."
    boltctl enroll --policy auto "$EGPU_UUID" 2>&1
fi

# Step 3: Authorize if not already authorized
if [ "$STATUS" != "authorized" ]; then
    echo "Authorizing eGPU..."
    boltctl authorize "$EGPU_UUID" 2>&1
    sleep 2
fi

# Step 4: PCI rescan to pick up the GPU
echo 1 > /sys/bus/pci/rescan
sleep 1

# Step 5: Wait up to 15s for the NVIDIA GPU to appear on PCI
for i in $(seq 1 15); do
    if lspci | grep -qi "nvidia"; then
        modprobe nvidia nvidia_drm nvidia_modeset nvidia_uvm
        echo "NVIDIA eGPU detected and drivers loaded"
        exit 0
    fi
    echo "Waiting for eGPU on PCI... ($i/15)"
    sleep 1
done

echo "No NVIDIA GPU detected after 15s, skipping driver load"
exit 0
