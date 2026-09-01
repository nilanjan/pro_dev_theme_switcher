APP  := dist/ProDev Theme Switcher.app
BIN  := .build/release/prodev-theme-switcher
VER  := 1.0
ROOT := $(HOME)/.config/prodev-theme-switcher
# Swift 6.4's default XCBuild backend needs full Xcode; this box has CLT only.
SWIFT_FLAGS := -c release --build-system native

.PHONY: all build app icon sign install install-config uninstall dmg check clean
all: app

build:
	swift build $(SWIFT_FLAGS)

icon: dist/AppIcon.icns
dist/AppIcon.icns:
	@mkdir -p dist/icon.iconset
	swift tools/mkicon.swift dist/icon-1024.png
	@for s in 16 32 64 128 256 512; do \
	  sips -z $$s $$s dist/icon-1024.png --out dist/icon.iconset/icon_$${s}x$${s}.png >/dev/null; \
	  sips -z $$((s*2)) $$((s*2)) dist/icon-1024.png --out dist/icon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns dist/icon.iconset -o dist/AppIcon.icns
	@rm -rf dist/icon.iconset dist/icon-1024.png

app: build icon
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp $(BIN) "$(APP)/Contents/MacOS/prodev-theme-switcher"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp dist/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	cp -R config "$(APP)/Contents/Resources/config"
	@$(MAKE) --no-print-directory sign
	@echo "built $(APP)"

sign:
	codesign --force --sign - --timestamp=none "$(APP)"

# The .app shells out to $(ROOT)/sync.sh, which is what actually knows how to
# theme Alacritty/tmux/nvim/herdr/Claude Code. The bundle carries a copy and lays
# it down on first launch; this is the same step from the repo, for a theme added
# under config/themes/ without rebuilding the app.
install-config:
	bash config/sync.sh --install

install: app install-config
	-@osascript -e 'quit app "ProDev Theme Switcher"' 2>/dev/null || true
	@sleep 1
	rm -rf "/Applications/ProDev Theme Switcher.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/ProDev Theme Switcher.app"
	@echo "installed. icon is in the menu bar."

# Backups stay: putting them back is the user's call, not a side effect.
uninstall:
	-@osascript -e 'quit app "ProDev Theme Switcher"' 2>/dev/null || true
	rm -rf "/Applications/ProDev Theme Switcher.app" "$(ROOT)/sync.sh" "$(ROOT)/themes" "$(ROOT)/nvim"
	defaults delete com.nilg.ProDevThemeSwitcher 2>/dev/null || true
	@echo "removed. Your pre-install configs are still in $(ROOT)/backup/original;"
	@echo "to put them back:  cp -Rp $(ROOT)/backup/original/. ~/"

dmg: app
	@rm -rf dist/stage "dist/ProDev-Theme-Switcher-$(VER).dmg"
	@mkdir -p dist/stage
	cp -R "$(APP)" dist/stage/
	ln -s /Applications dist/stage/Applications
	hdiutil create -volname "ProDev Theme Switcher" -srcfolder dist/stage \
	  -ov -format UDZO "dist/ProDev-Theme-Switcher-$(VER).dmg"
	@rm -rf dist/stage
	@echo "dist/ProDev-Theme-Switcher-$(VER).dmg"

check:
	./check.sh

clean:
	rm -rf .build dist
