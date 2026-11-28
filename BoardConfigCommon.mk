#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0
#

# Silence errors/warnings
DISABLE_ARTIFACT_PATH_REQUIREMENTS := true
BUILD_BROKEN_DUP_RULES := true

# Security - must be defined before including BoardConfig-common.mk
BOOT_SECURITY_PATCH := 2026-10-05
VENDOR_SECURITY_PATCH := $(BOOT_SECURITY_PATCH)

# Kernel
BOARD_KERNEL_CMDLINE += \
    fips140.load_sequential=1 \
    exynos_drm.load_sequential=1 \
    g2d.load_sequential=1 \
    samsung_iommu_v9.load_sequential=1 \
    vh_sched.load_sequential=1 \
    pcie_exynos_gs.load_sequential=1

include device/google/zumapro/BoardConfig-common.mk

# Kernel modules
BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_BLOCKLIST_FILE := $(DEVICE_PATH)/recovery/modules.blocklist.vendor_kernel_boot
BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_LOAD_RAW := $(strip $(shell cat $(DEVICE_PATH)/recovery/modules.load.vendor_kernel_boot))
BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_LOAD += $(BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_LOAD_RAW)
BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES += $(addprefix $(KERNEL_MODULE_DIR)/, $(notdir $(BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_LOAD_RAW)))

# SEPolicy
BOARD_VENDOR_SEPOLICY_DIRS += \
    $(DEVICE_PATH)/sepolicy/vendor \
    hardware/google/pixel-sepolicy/vibrator/common \
    hardware/google/pixel-sepolicy/vibrator/cs40l26

# WiFi
include $(DEVICE_PATH)/wifi/BoardConfig-wifi.mk

# ---------------------------------------------------------------------------
# Anaconda custom kernel
#
# Build Image.lz4 + dtb.img + dtbo.img inline from kernel/google/zumapro.
# Kernel modules keep coming from the caimito-kernels prebuilt set populated by
# the separate out-of-tree LineageOS kernel build (the KERNEL_MODULE_DIR and
# BOARD_*_KERNEL_MODULES wiring from the zumapro include above is untouched).
# Rules live in $(DEVICE_PATH)/kernel/ ; nothing outside device/ is modified.
# ---------------------------------------------------------------------------
include $(DEVICE_PATH)/kernel/anaconda-kernel-defs.mk

ifeq ($(TARGET_ANACONDA_KERNEL),true)
# IMPORTANT: TARGET_NO_KERNEL stays true (inherited from zumapro). That keeps
# lineage build_kernel() (gs-6.1) running at lunch to produce the module
# prebuilts in caimito-kernels. We therefore do NOT let AOSP assemble boot.img;
# instead kernel/anaconda-kernel.mk reassembles it (anaconda Image.lz4 + dtb +
# the gs-6.1 prebuilt's ramdisk) and we point BOARD_PREBUILT_BOOTIMAGE at it.
# AOSP copies that boot.img to $(PRODUCT_OUT)/boot.img and re-signs it (AVB).
BOARD_PREBUILT_BOOTIMAGE := $(ANACONDA_KERNEL_BOOT_IMAGE)

# Own the dtb.img recipe: clearing the prebuilt dir makes AOSP declare
# INSTALLED_DTBIMAGE_TARGET without a recipe, which anaconda-kernel.mk then
# provides (cat of the anaconda zumapro base dtbs). AOSP bakes it into
# vendor_kernel_boot (boot header v4 -> dtb is not carried in boot.img).
BOARD_PREBUILT_DTBIMAGE_DIR :=

# dtbo.img is left as the gs-6.1 prebuilt: BOARD_PREBUILT_DTBOIMAGE inherited from
# the zumapro BoardConfig (= caimito-kernels/<ver>/dtbo.img) is kept as-is. The
# anaconda plain-make build produces no dtbo overlays (the komodo/caiman/tokay
# overlays are Kleaf-only, built only by the gs-6.1 kernel flow).
endif
