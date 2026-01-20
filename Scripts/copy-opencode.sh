#!/bin/sh
set -euo pipefail

SOURCE="${PROJECT_DIR}/Motive/Resources/opencode"
if [ -n "${OPENCODE_BINARY_PATH:-}" ]; then
  SOURCE="${OPENCODE_BINARY_PATH}"
fi

DEST="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/opencode"

if [ ! -f "${SOURCE}" ]; then
  echo "warning: OpenCode binary not found at ${SOURCE}."
  echo "warning: Provide ${PROJECT_DIR}/Motive/Resources/opencode or set OPENCODE_BINARY_PATH."
  exit 0
fi

cp -f "${SOURCE}" "${DEST}"
chmod +x "${DEST}"

if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${DEST}"
else
  /usr/bin/codesign --force --sign - "${DEST}"
fi
