#
# SPDX-FileCopyrightText: The Mist-OS Project
# SPDX-License-Identifier: Apache-2.0
#
# Inline anaconda kernel build, wired in through the AOSP task_makefiles glob
# (build/make/core/Makefile: $(wildcard device/*/*/build/tasks/*.mk)). This runs
# at the END of core/Makefile, after INSTALLED_KERNEL_TARGET /
# INSTALLED_DTBIMAGE_TARGET / mkdtimg / HOST_OUT_EXECUTABLES are defined.
#
# It is NOT an Android.mk, so it is not subject to the androidmk denylist that
# blocks Android.mk under device/google/ (build/soong/ui/build/androidmk_denylist.go).
#
# The actual rules live in kernel/anaconda-kernel.mk (kept separate so the
# path-only defs can also be included from the BoardConfig phase).
#
include device/google/caimito/kernel/anaconda-kernel.mk
