TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = USBMirror
USBMirror_FILES = H264Server.mm TouchServer.xm ../vendor/zxtouchrootless-main/pccontrol/Touch.xm ../vendor/zxtouchrootless-main/pccontrol/Screen.xm ../vendor/zxtouchrootless-main/pccontrol/Common.xm
USBMirror_CFLAGS = -fobjc-arc -Wno-error -Wno-deprecated-declarations -Wno-unused-function -Wno-module-import-in-extern-c -I. -I../vendor/zxtouchrootless-main/pccontrol
USBMirror_FRAMEWORKS = UIKit Foundation IOSurface VideoToolbox CoreMedia CoreVideo CoreGraphics
USBMirror_PRIVATE_FRAMEWORKS = IOKit
USBMirror_LIBRARIES = substrate
USBMirror_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/tweak.mk
