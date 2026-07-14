# Copyright (c) 2024-2026 protocentral
# SPDX-License-Identifier: MIT

flutter build ios --release --no-codesign
cd ios
fastlane ios beta
