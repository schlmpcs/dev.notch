#!/bin/sh
# Compiles the pure (Foundation-only) logic files together with the check
# entry point and runs them. Deliberately independent of Xcode so the logic
# has a red/green cycle without adding a test target.
set -e
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/selfcheck"
swiftc -o "$OUT" \
  boringNotch/devstatus/VPNClassifier.swift \
  boringNotch/devstatus/AgentSessionState.swift \
  boringNotch/devstatus/HomeMiddlePanel.swift \
  Scripts/selfcheck/main.swift
"$OUT"
