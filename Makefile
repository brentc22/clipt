APP      := Clipt
BUNDLE   := $(APP).app
CONTENTS := $(BUNDLE)/Contents
BIN_DIR   = $(shell swift build -c release --product $(APP) --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null)

.PHONY: all build bundle install run test zip icon clean

all: bundle

# Universal binary so the release zip runs on Intel and Apple silicon.
build:
	swift build -c release --product $(APP) --arch arm64 --arch x86_64

# Signs with "Clipt Self-Signed" (scripts/make-signing-cert.sh). There is no silent
# ad-hoc fallback: an ad-hoc signature changes identity every build and macOS drops
# the Accessibility grant. CI passes CLIPT_SIGN_IDENTITY=- explicitly, for
# verification only.
bundle: build
	@id="$${CLIPT_SIGN_IDENTITY:-}"; \
	if [ -z "$$id" ]; then \
		if security find-identity -p codesigning 2>/dev/null | grep -q "Clipt Self-Signed"; then id="Clipt Self-Signed"; \
		else echo "error: no 'Clipt Self-Signed' signing identity. Run scripts/make-signing-cert.sh, or pass CLIPT_SIGN_IDENTITY=- for a throwaway ad-hoc build." >&2; exit 1; fi; \
	fi; \
	rm -rf $(BUNDLE); \
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources; \
	cp $(BIN_DIR)/$(APP) $(CONTENTS)/MacOS/$(APP); \
	cp Resources/Info.plist $(CONTENTS)/Info.plist; \
	if [ -f Resources/$(APP).icns ]; then cp Resources/$(APP).icns $(CONTENTS)/Resources/$(APP).icns; fi; \
	codesign --force --sign "$$id" $(BUNDLE) && echo "signed with: $$id"

install: bundle
	@pkill -x $(APP) 2>/dev/null || true
	rm -rf /Applications/$(BUNDLE)
	cp -R $(BUNDLE) /Applications/
	@echo "installed /Applications/$(BUNDLE)"

run: install
	open /Applications/$(BUNDLE)

test:
	swift run CliptTests

zip: bundle
	ditto -c -k --keepParent $(BUNDLE) $(APP).zip

icon:
	swift scripts/make-icon.swift
	iconutil -c icns Resources/$(APP).iconset -o Resources/$(APP).icns
	rm -rf Resources/$(APP).iconset

clean:
	rm -rf .build $(BUNDLE) $(APP).zip
