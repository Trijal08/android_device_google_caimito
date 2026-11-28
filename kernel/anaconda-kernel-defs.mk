#
# SPDX-FileCopyrightText: The Mist-OS Project
# SPDX-License-Identifier: Apache-2.0
#
# Anaconda custom kernel — shared path/flag definitions.
#
# This file is intentionally side-effect free (variables only) so it can be
# included safely from BOTH the BoardConfig phase and the Android.mk/rules
# phase without defining any make rules or touching non-device-specific trees.
#
# Split of responsibilities:
#   * Anaconda source (kernel/google/zumapro)  -> Image.lz4 + dtb.img + dtbo.img
#   * LineageOS out-of-tree kernel build (prebuilt .ko in caimito-kernels/<ver>)
#                                               -> kernel modules ONLY (unchanged)
#

# Master switch. Set to false to fall back to the stock prebuilt-kernel flow.
TARGET_ANACONDA_KERNEL ?= true

# Where the custom (anaconda) kernel source lives inside the ROM tree.
ANACONDA_KERNEL_SRC := kernel/google/zumapro

# Defconfig consumed by the inline build (arch/arm64/configs/<this>).
ANACONDA_KERNEL_DEFCONFIG ?= zumapro_defconfig

# Out-of-source (O=) build directory for the inline kernel build.
# OUT_DIR and TARGET_DEVICE are both defined at BoardConfig time, so this
# resolves identically in the BoardConfig phase and the rules phase, and lands
# under the normal product out tree (cleaned by `m installclean`/`m clobber`).
ANACONDA_KERNEL_OUT := $(OUT_DIR)/target/product/$(TARGET_DEVICE)/obj/ANACONDA_KERNEL

# Artifacts produced by the inline build.
ANACONDA_KERNEL_IMAGE := $(ANACONDA_KERNEL_OUT)/arch/arm64/boot/Image.lz4
# The anaconda plain-make build emits its base SoC dtbs HERE (google-devices/
# zumapro/dts), NOT arch/arm64/boot/dts. These 4 zumapro-{a0,a1}-{foplp,ipop}.dtb
# are komodo's device trees; AOSP concatenates *.dtb into dtb.img and bakes it
# into vendor_kernel_boot (per the user: dtb = cat of out/google-devices/zumapro/
# dts/*.dtb). Overridable.
ANACONDA_KERNEL_DTB_DIR  ?= $(ANACONDA_KERNEL_OUT)/google-devices/zumapro/dts
ANACONDA_KERNEL_DTB_GLOB ?= *.dtb

# Final images assembled by our rules and handed to AOSP's standard image/AVB
# machinery. The dtb.img is built straight into AOSP's INSTALLED_DTBIMAGE_TARGET
# ($(PRODUCT_OUT)/dtb.img); AOSP bakes it into vendor_kernel_boot (boot header is
# v4 -> the dtb is NOT carried in boot.img). boot.img = template with ONLY the
# kernel swapped, via BOARD_PREBUILT_BOOTIMAGE.
#
# dtbo.img is deliberately NOT produced here: the anaconda plain-make build has no
# dtbo overlay sources (the komodo/caiman/tokay overlays are Kleaf-only, built
# only by the gs-6.1 flow). dtbo.img stays the gs-6.1 prebuilt — BOARD_PREBUILT_
# DTBOIMAGE inherited from the zumapro BoardConfig = caimito-kernels/<ver>/dtbo.img.
ANACONDA_KERNEL_BOOT_IMAGE := $(ANACONDA_KERNEL_OUT)/boot.img

# Template boot.img whose ramdisk/cmdline/os_version/header we reuse: the gs-6.1
# prebuilt that lineage build_kernel() drops into caimito-kernels. Overridable.
ANACONDA_KERNEL_BOOT_TEMPLATE ?= $(TARGET_KERNEL_DIR)/boot.img

# Toolchain flags for the inline build. Mirrors the known-good manual invocation
# (LLVM/clang, ld.lld). Override ANACONDA_KERNEL_CC to use e.g. "ccache clang".
# NOTE: do NOT call host `nproc`/`make` here — they are Forbidden PATH tools in
# the Soong/siso action sandbox. Job count + make binary are resolved in
# anaconda-kernel.mk via toybox / $(KERNEL_MAKE_CMD) (allowlisted prebuilts).
ANACONDA_KERNEL_CC   ?= clang

# Host perl used to SHADOW the prebuilt tools-lineage perl during the kernel
# build. That prebuilt perl is unusable on modern hosts (it needs libcrypt.so.1,
# which libxcrypt-based distros no longer ship) AND its PERL5LIB perl-base is
# 5.26 vs a typical host perl 5.44, so PERL5LIB must be cleared too. The kernel's
# perl codegen (perlasm sha/poly, build_OID_registry) uses only core modules, so
# the host perl's own @INC is sufficient. Override if host perl lives elsewhere.
# anaconda-kernel.mk symlinks $(ANACONDA_KERNEL_PERLBIN)/perl -> this and prepends
# that dir to the sub-make PATH (so BOTH $(PERL) and bare-`perl` rules use it).
ANACONDA_HOST_PERL       ?= /usr/bin/perl
ANACONDA_KERNEL_PERLBIN  := $(ANACONDA_KERNEL_OUT)/perlbin
