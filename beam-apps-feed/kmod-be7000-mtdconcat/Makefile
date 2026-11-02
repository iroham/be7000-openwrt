include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=kmod-be7000-mtdconcat
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=Timofey Maykov <itnitro@gmail.com>

include $(INCLUDE_DIR)/package.mk

define KernelPackage/be7000-mtdconcat
  SECTION:=kernel
  CATEGORY:=Kernel modules
  SUBMENU:=Other modules
  TITLE:=Glue MTD partitions into one device
  FILES:=$(PKG_BUILD_DIR)/be7000-mtdconcat.ko
endef

define KernelPackage/be7000-mtdconcat/description
 Concatenates MTD partitions given by name into one MTD device, so that a
 single UBI device can span them. On the Xiaomi BE7000 it lets /overlay
 use the spare firmware slot and the data partition together. Loaded by
 /lib/preinit/77_be7000_slot_storage, not at boot.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

$(eval $(call KernelPackage,be7000-mtdconcat))
