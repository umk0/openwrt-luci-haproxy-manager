include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-haproxy-manager
PKG_VERSION:=0.4.0
PKG_RELEASE:=2
PKG_LICENSE:=MIT
PKG_MAINTAINER:=HAProxy Manager contributors
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-haproxy-manager
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI HAProxy Manager
  DEPENDS:=+luci-base +rpcd +rpcd-mod-file +haproxy
endef

define Package/luci-app-haproxy-manager/description
  LuCI application for managing HTTP Host, HTTPS SNI, and TCP HAProxy routes,
  with validation, backups, and rollback on OpenWrt.
endef

define Package/luci-app-haproxy-manager/conffiles
/etc/config/haproxy_manager
/etc/haproxy.cfg
endef

define Build/Compile
	python3 ./build-lmo.py .
endef

define Package/luci-app-haproxy-manager/install
	$(INSTALL_DIR) $(1)/
	$(CP) ./root/* $(1)/
	$(INSTALL_DIR) $(1)/www
	$(CP) ./htdocs/* $(1)/www/
endef

define Package/luci-app-haproxy-manager/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
chmod +x /usr/libexec/haproxy-manager/* 2>/dev/null || true
/usr/libexec/haproxy-manager/migrate >/dev/null 2>&1 || logger -t haproxy-manager "Configuration migration failed"
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
endef

define Package/luci-app-haproxy-manager/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
endef

$(eval $(call BuildPackage,luci-app-haproxy-manager))

define HaproxyManagerI18nPackage
  define Package/luci-i18n-haproxy-manager-$(1)
    SECTION:=luci
    CATEGORY:=LuCI
    SUBMENU:=Translations
    TITLE:=$(2) language support for LuCI HAProxy Manager
    DEPENDS:=+luci-app-haproxy-manager
    PKGARCH:=all
  endef

  define Package/luci-i18n-haproxy-manager-$(1)/description
    $(2) translation package for luci-app-haproxy-manager.
  endef

  define Package/luci-i18n-haproxy-manager-$(1)/install
	$$(INSTALL_DIR) $$(1)/
	$$(CP) ./i18n/$(1)/* $$(1)/
  endef

  define Package/luci-i18n-haproxy-manager-$(1)/postinst
#!/bin/sh
[ -n "$$$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
  endef

  define Package/luci-i18n-haproxy-manager-$(1)/postrm
#!/bin/sh
[ -n "$$$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
  endef

  $$(eval $$(call BuildPackage,luci-i18n-haproxy-manager-$(1)))
endef

$(eval $(call HaproxyManagerI18nPackage,ru,Russian))
$(eval $(call HaproxyManagerI18nPackage,es,Spanish))
$(eval $(call HaproxyManagerI18nPackage,ko,Korean))
$(eval $(call HaproxyManagerI18nPackage,ja,Japanese))
$(eval $(call HaproxyManagerI18nPackage,zh-cn,Simplified Chinese))
