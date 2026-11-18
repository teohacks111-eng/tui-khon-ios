#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

if [[ -f "$HOME/.local/share/swiftly/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.local/share/swiftly/env.sh"
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "ERROR: Không tìm thấy Swift trong Ubuntu WSL." >&2
    exit 10
fi

if [[ ! -x "$HOME/xtool" ]]; then
    echo "ERROR: Không tìm thấy xtool tại $HOME/xtool." >&2
    exit 11
fi

BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
if [[ "$BUILD_CONFIGURATION" != "debug" && "$BUILD_CONFIGURATION" != "release" ]]; then
    echo "ERROR: BUILD_CONFIGURATION chỉ nhận debug hoặc release." >&2
    exit 13
fi

echo "== Swift tests =="
swift test

echo "== Build unsigned IPA =="
export APPIMAGE_EXTRACT_AND_RUN=1
"$HOME/xtool" dev build --configuration "$BUILD_CONFIGURATION" --ipa

mkdir -p artifacts
ipa_source="$(find xtool -maxdepth 1 -type f -name '*.ipa' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)"
if [[ -z "$ipa_source" || ! -s "$ipa_source" ]]; then
    echo "ERROR: xtool không tạo ra file IPA hợp lệ." >&2
    exit 12
fi

ipa_name="TuiKhon-$BUILD_CONFIGURATION.ipa"
cp "$ipa_source" "artifacts/$ipa_name"
echo "IPA_OUTPUT=$PROJECT_DIR/artifacts/$ipa_name"
