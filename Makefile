TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AndroNavBar
AndroNavBar_FILES = Tweak.xm ANVBarController.m ANVGlyphView.m ANVActions.m ANVHistory.m ANVSettings.m ANVMusicMonitor.m ANVSpectrumView.m
AndroNavBar_CFLAGS = -fobjc-arc
AndroNavBar_FRAMEWORKS = UIKit QuartzCore AVFoundation Accelerate
AndroNavBar_PRIVATE_FRAMEWORKS =

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
