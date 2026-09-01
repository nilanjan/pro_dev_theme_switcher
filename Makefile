APP  := dist/NG-Thm-Ch.app
BIN  := .build/release/ng-thm-ch
VER  := 1.0
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
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/ng-thm-ch
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp dist/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	@$(MAKE) --no-print-directory sign
	@echo "built $(APP)"

sign:
	codesign --force --sign - --timestamp=none $(APP)

# The .app is inert without these: it shells out to ~/.config/theme-sync-all.sh,
# which is what actually knows how to theme Alacritty/tmux/nvim/herdr/Claude Code.
# Existing files are backed up to *.ngthmch.bak rather than clobbered.
install-config:
	@set -e; \
	bk(){ [ -f "$$1" ] && [ ! -f "$$1.ngthmch.bak" ] && cp "$$1" "$$1.ngthmch.bak" || true; }; \
	mkdir -p ~/.config/alacritty/themes/custom ~/.tmux/themes ~/.config/nvim/lua/themes; \
	bk ~/.config/theme-sync-all.sh;                        cp config/theme-sync-all.sh    ~/.config/theme-sync-all.sh; \
	chmod +x ~/.config/theme-sync-all.sh; \
	bk ~/.config/alacritty/themes/custom/dark.toml;        cp config/alacritty/dark.toml  ~/.config/alacritty/themes/custom/dark.toml; \
	bk ~/.config/alacritty/themes/custom/light.toml;       cp config/alacritty/light.toml ~/.config/alacritty/themes/custom/light.toml; \
	bk ~/.tmux/themes/dark.conf;                           cp config/tmux/dark.conf       ~/.tmux/themes/dark.conf; \
	bk ~/.tmux/themes/light.conf;                          cp config/tmux/light.conf      ~/.tmux/themes/light.conf; \
	cp config/nvim/rose-pine-dawn.lua   ~/.config/nvim/lua/themes/; \
	cp config/nvim/tokyonight-storm.lua ~/.config/nvim/lua/themes/
	@echo "config installed. Apply config/nvim/EDITS.md by hand for live nvim reload."

install: app install-config
	-@osascript -e 'quit app "NG-Thm-Ch"' 2>/dev/null || true
	@sleep 1
	rm -rf /Applications/NG-Thm-Ch.app
	cp -R $(APP) /Applications/
	open /Applications/NG-Thm-Ch.app
	@echo "installed. icon is in the menu bar."

uninstall:
	-@osascript -e 'quit app "NG-Thm-Ch"' 2>/dev/null || true
	rm -rf /Applications/NG-Thm-Ch.app
	defaults delete com.nilg.NG-Thm-Ch 2>/dev/null || true
	@echo "removed."

dmg: app
	@rm -rf dist/stage dist/NG-Thm-Ch-$(VER).dmg
	@mkdir -p dist/stage
	cp -R $(APP) dist/stage/
	ln -s /Applications dist/stage/Applications
	hdiutil create -volname "NG-Thm-Ch" -srcfolder dist/stage \
	  -ov -format UDZO dist/NG-Thm-Ch-$(VER).dmg
	@rm -rf dist/stage
	@echo "dist/NG-Thm-Ch-$(VER).dmg"

check:
	./check.sh

clean:
	rm -rf .build dist
