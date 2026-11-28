#
# SPDX-FileCopyrightText: The Mist-OS Project
# SPDX-License-Identifier: Apache-2.0
#
# Anaconda custom kernel — inline build rules.
#
# Compiles the kernel source at kernel/google/zumapro during the normal ROM
# build and feeds ONLY the kernel image (via a reassembled boot.img), the
# vendor_boot dtb.img and the dtbo.img into the image build. Kernel modules
# (.ko) are untouched and keep coming from device/google/caimito-kernels/<ver>,
# which is populated by lineage's build_kernel() (gs-6.1) at lunch time.
#
# TARGET_NO_KERNEL stays true (so build_kernel keeps producing the modules),
# which means the boot image is a whole prebuilt (BOARD_PREBUILT_BOOTIMAGE). We
# therefore reassemble it: take the gs-6.1 prebuilt boot.img as a template and
# swap in anaconda's Image.lz4 + dtb, keeping its ramdisk/header. AOSP then
# copies that boot.img to $(PRODUCT_OUT)/boot.img and re-signs it with the ROM
# AVB key. No non-device-specific tree is modified.
#
# Delivered artifacts:
#   $(ANACONDA_KERNEL_BOOT_IMAGE)  -> BOARD_PREBUILT_BOOTIMAGE  (boot.img)
#   $(INSTALLED_DTBIMAGE_TARGET)   -> vendor_boot dtb (BOARD_PREBUILT_DTBIMAGE_DIR
#                                     cleared so AOSP declares it recipe-less)
#   $(ANACONDA_KERNEL_DTBO_IMAGE)  -> BOARD_PREBUILT_DTBOIMAGE  (dtbo.img)
#

LOCAL_PATH := $(call my-dir)
include $(LOCAL_PATH)/anaconda-kernel-defs.mk

ifeq ($(TARGET_ANACONDA_KERNEL),true)

# Reuse lineage's kernel build configuration verbatim rather than maintaining a
# second copy. KERNEL_MAKE_CMD, KERNEL_MAKE_FLAGS and TOOLS_PATH_OVERRIDE are
# defined unconditionally in vendor/lineage/config/BoardConfigKernel.mk (only the
# kernel.mk build *task* is gated off here by TARGET_NO_KERNEL). They already
# provide the hermetic toolchain and every host-tool flag a sandbox kernel build
# needs — PAHOLE / LZ4 / LEX / YACC / M4 (bare tools are Forbidden PATH tools),
# HOSTCFLAGS/HOSTLDFLAGS (libelf + glibc sysroot), the clang/rust/build-tools
# PATH, perl-base, and Pixel-matching KBUILD_BUILD_USER/HOST. This is exactly how
# lineage's own inline builder (internal-make-kernel-target) drives the kernel.
ANACONDA_KERNEL_MAKE := \
    $(if $(strip $(KERNEL_MAKE_CMD)),$(KERNEL_MAKE_CMD),$(abspath prebuilts/build-tools/$(HOST_PREBUILT_TAG)/bin)/make)
ANACONDA_KERNEL_TOYBOX := $(abspath prebuilts/build-tools/$(HOST_PREBUILT_TAG)/bin)/toybox

# Extra make flags appended last (override). e.g. ANACONDA_KERNEL_EXTRA_MAKE_FLAGS
# := HOSTCFLAGS="..." to replace the default hermetic HOSTCFLAGS.
ANACONDA_KERNEL_EXTRA_MAKE_FLAGS ?=

ANACONDA_KERNEL_STAMP := $(ANACONDA_KERNEL_OUT)/.anaconda_build_stamp

# Perl fix: the prebuilt perl in $(TOOLS_PATH_OVERRIDE)'s PATH can't run on modern
# hosts (needs libcrypt.so.1) and its PERL5LIB (perl-base 5.26) mismatches the
# host perl (5.44). Clear PERL5LIB, and prepend $(ANACONDA_KERNEL_PERLBIN) (holds
# a `perl` -> host-perl symlink, created in the stamp recipe) to the sub-make
# PATH so EVERY perl invocation — $(PERL) rules (perlasm) AND bare-`perl` rules
# (lib/Makefile build_OID_registry) — resolves to the host perl. The /bin/sh -c
# wrapper prepends AFTER TOOLS_PATH_OVERRIDE has set PATH (keeping clang/rust/
# build-tools), then execs make with the original flags/args untouched. /bin/sh
# and the host perl are absolute paths, so the siso PATH-tool deny-wrapper (which
# only governs bare command names) does not intercept them.
#
# -j is appended at recipe time (parse-time nproc/getconf can run in a
# CPU-limited context); it comes last so it overrides KERNEL_MAKE_FLAGS' own -j.
_anaconda_make := \
    $(TOOLS_PATH_OVERRIDE) PERL5LIB= \
    /bin/sh -c 'PATH=$(abspath $(ANACONDA_KERNEL_PERLBIN)):$$PATH exec "$$0" "$$@"' \
    $(ANACONDA_KERNEL_MAKE) $(KERNEL_MAKE_FLAGS) \
        -C $(abspath $(ANACONDA_KERNEL_SRC)) \
        O=$(abspath $(ANACONDA_KERNEL_OUT)) \
        ARCH=arm64 CC="$(ANACONDA_KERNEL_CC)" LD=ld.lld \
        $(ANACONDA_KERNEL_EXTRA_MAKE_FLAGS) \
        LOCALVERSION=

# ---- Compile the kernel (Image.lz4 + in-tree dtbs/dtbos) --------------------
# Single stamp drives all artifacts so the (expensive) build runs once.
$(ANACONDA_KERNEL_STAMP):
	@echo "Anaconda kernel: building from $(ANACONDA_KERNEL_SRC) ($(ANACONDA_KERNEL_DEFCONFIG))"
	@mkdir -p $(ANACONDA_KERNEL_OUT)
	@test -x $(ANACONDA_HOST_PERL) || { \
	    echo "Anaconda kernel: ERROR host perl not executable: $(ANACONDA_HOST_PERL) (set ANACONDA_HOST_PERL)" >&2; exit 1; }
	@mkdir -p $(ANACONDA_KERNEL_PERLBIN)
	@$(ANACONDA_KERNEL_TOYBOX) ln -sf $(ANACONDA_HOST_PERL) $(ANACONDA_KERNEL_PERLBIN)/perl
	njobs=`$(ANACONDA_KERNEL_TOYBOX) nproc 2>/dev/null || echo 8`; \
	 $(_anaconda_make) -j$$njobs $(ANACONDA_KERNEL_DEFCONFIG) && \
	 $(_anaconda_make) -j$$njobs
	@test -f $(ANACONDA_KERNEL_IMAGE) || { \
	    echo "Anaconda kernel: ERROR expected image not found at $(ANACONDA_KERNEL_IMAGE)" >&2; exit 1; }
	@touch $@

$(ANACONDA_KERNEL_IMAGE): $(ANACONDA_KERNEL_STAMP)
	@test -f $@

# ---- 1) dtb.img (anaconda base dtbs) -> $(INSTALLED_DTBIMAGE_TARGET) --------
# AOSP bakes this into vendor_kernel_boot (boot header v4: the dtb is NOT in
# boot.img). dtb.img is just the concatenation of the anaconda zumapro base dtbs.
# Runtime glob (not parse-time) so freshly built dtbs are picked up.
$(INSTALLED_DTBIMAGE_TARGET): $(ANACONDA_KERNEL_STAMP)
	@echo "Anaconda kernel: assemble dtb.img (-> vendor_kernel_boot) -> $@"
	@mkdir -p $(dir $@)
	@dtbs=`find $(ANACONDA_KERNEL_DTB_DIR) -name '$(ANACONDA_KERNEL_DTB_GLOB)' | sort`; \
	 if [ -z "$$dtbs" ]; then \
	    echo "Anaconda kernel: ERROR no dtb under $(ANACONDA_KERNEL_DTB_DIR)" >&2; exit 1; fi; \
	 cat $$dtbs > $@

# ---- 2) boot.img: anaconda Image.lz4 + template ramdisk (kernel swap ONLY) --
# Template = the gs-6.1 prebuilt boot.img (build_kernel output): a v4 image of
# kernel + empty ramdisk, NO dtb (dtb lives in vendor_kernel_boot). We unpack it
# to reuse its header/ramdisk/cmdline and repack with ONLY the kernel swapped to
# anaconda's Image.lz4 (--kernel appended last overrides the template's; argparse
# last-wins). AOSP (BOARD_PREBUILT_BOOTIMAGE path) copies + AVB-signs the result.
$(ANACONDA_KERNEL_BOOT_IMAGE): $(ANACONDA_KERNEL_STAMP) $(MKBOOTIMG) $(UNPACK_BOOTIMG)
	@echo "Anaconda kernel: reassemble boot.img (kernel swap) -> $@"
	@test -f $(ANACONDA_KERNEL_BOOT_TEMPLATE) || { \
	    echo "Anaconda kernel: ERROR template boot.img missing: $(ANACONDA_KERNEL_BOOT_TEMPLATE)" >&2; \
	    echo "  (lineage build_kernel() must have populated caimito-kernels first)" >&2; exit 1; }
	@mkdir -p $(dir $@)
	@rm -rf $(ANACONDA_KERNEL_OUT)/bootimg_unpack
	@args=`$(UNPACK_BOOTIMG) --boot_img $(ANACONDA_KERNEL_BOOT_TEMPLATE) \
	    --out $(ANACONDA_KERNEL_OUT)/bootimg_unpack --format=mkbootimg`; \
	 eval $(MKBOOTIMG) $$args \
	    --kernel $(ANACONDA_KERNEL_IMAGE) \
	    --output $@

.PHONY: anaconda-kernel
anaconda-kernel: $(ANACONDA_KERNEL_BOOT_IMAGE) $(INSTALLED_DTBIMAGE_TARGET)

endif # TARGET_ANACONDA_KERNEL
