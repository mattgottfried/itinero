#!/bin/bash
# Archive, export and (optionally) upload Itinero to App Store Connect / TestFlight.
#
#   tools/release.sh            archive + export an .ipa into build/ (no upload)
#   tools/release.sh --upload   also upload, using an App Store Connect API key:
#                               export ASC_KEY_PATH=~/keys/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=xxxx-...
#                               (or be signed in to Xcode → Settings → Accounts with App Store Connect access)
# Bump CURRENT_PROJECT_VERSION in project.yml before each new upload (build numbers must increase).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "brew install xcodegen"; exit 1; }
xcodegen generate

OUT=build/release; rm -rf "$OUT"; mkdir -p "$OUT"
AUTH=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

xcodebuild archive -project Itinero.xcodeproj -scheme Itinero -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Itinero.xcarchive" -allowProvisioningUpdates "${AUTH[@]}"

DEST=export; [[ "${1:-}" == "--upload" ]] && DEST=upload
sed "s|<string>export</string>|<string>$DEST</string>|" tools/ExportOptions.plist > "$OUT/ExportOptions.plist"
xcodebuild -exportArchive -archivePath "$OUT/Itinero.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates "${AUTH[@]}"

[[ "$DEST" == "export" ]] && echo "IPA: $OUT/export/Itinero.ipa  (upload with Transporter, or rerun with --upload)"
