# Field Notes for Android: the commands, one make target each. `make` alone lists them. Run them
# in this folder.
#
# The bridge (../bridge) runs on this desktop while Field Notes' Settings > Draw from a phone is on; the app runs on the phone, and adb links the two over USB or Wireless
# debugging. Nothing here writes outside the repository except the pairing token, which the
# bridge keeps in ~/.local/state/fieldnotes-bridge.

SHELL  := /bin/sh
ADB    ?= $(HOME)/Android/Sdk/platform-tools/adb
BRIDGE := python3 $(CURDIR)/../bridge/fieldnotes-bridge

.PHONY: help bridge run logs test

help:
	@echo "Field Notes for Android"
	@echo ""
	@echo "  make bridge   run the desktop bridge by hand, with Field Notes' switch off (Ctrl+C stops it)"
	@echo "  make run      build the app, install it on every connected phone, pair it and open it"
	@echo "  make logs     follow the app's log"
	@echo "  make test     the bridge's tests, the app's tests and lint"
	@echo ""
	@echo "  ANDROID_SERIAL=<serial> picks one phone when adb lists more than one."
	@echo "  ADB=$(ADB)"

bridge:
	$(BRIDGE) --adb "$(ADB)"

# installDebug finds adb through local.properties and installs on every listed phone, or on
# ANDROID_SERIAL alone. --pair gives the app this desktop's token and opens it; the app keeps it.
run:
	./gradlew installDebug
	$(BRIDGE) --pair --adb "$(ADB)"

# A tag filter survives the restart every make run causes; a pid filter would not.
logs:
	"$(ADB)" logcat -v time -s FieldNotes:V AndroidRuntime:E

test:
	python3 -m unittest discover -s ../bridge
	./gradlew testDebugUnitTest lintDebug
