# Navigate to lambda directory
cd terraform/lambda

rm -v *.zip
# Zip each function (required for Terraform deployment)
zip start_step_function.zip start_step_function.py
zip parse_email.zip parse_email.py
zip invoke_bedrock.zip invoke_bedrock.py
zip extract_business.zip extract_business.py
zip save_to_dynamodb.zip save_to_dynamodb.py

#!/bin/bash
set -e  # Exit immediately if any command fails

##############################################################################
# Lambda Layer Build Script for chardet
# Purpose: Create a properly structured Lambda layer for email encoding detection
# Compatibility: Python 3.11 (matches Lambda runtime)
# Output: lambda/layers/chardet-layer.zip
##############################################################################

# -------------------------- Configuration --------------------------
# Target Python version (must match Lambda runtime)
PYTHON_VERSION="python3.11"
# Layer output directory
LAYER_DIR="layers"
# Temporary build directory
BUILD_DIR="${LAYER_DIR}/build"
# Final layer zip name
LAYER_ZIP="chardet-layer.zip"

# -------------------------- Step 1: Clean previous builds --------------------------
echo "=== Step 1: Cleaning previous build files ==="
rm -rf "${BUILD_DIR}"
rm -f "${LAYER_DIR}/${LAYER_ZIP}"
mkdir -p "${BUILD_DIR}"

# -------------------------- Step 2: Create layer directory structure --------------------------
# Lambda requires layers to follow: python/lib/<python-version>/site-packages
echo "=== Step 2: Creating Lambda layer directory structure ==="
LAYER_PYTHON_DIR="${BUILD_DIR}/python/lib/${PYTHON_VERSION}/site-packages"
mkdir -p "${LAYER_PYTHON_DIR}"

# -------------------------- Step 3: Install chardet to layer directory --------------------------
echo "=== Step 3: Installing chardet to layer directory ==="
pip install \
  --target "${LAYER_PYTHON_DIR}" \
  --upgrade \
  --no-cache-dir \
  chardet==5.2.0  # Pin version for stability

# -------------------------- Step 4: Remove unnecessary files (reduce layer size) --------------------------
echo "=== Step 4: Optimizing layer size ==="
# Remove cache files
rm -rf "${LAYER_PYTHON_DIR}/__pycache__"
rm -rf "${LAYER_PYTHON_DIR}/chardet/__pycache__"
# Remove dist-info (not required for Lambda)
rm -rf "${LAYER_PYTHON_DIR}/chardet-*.dist-info"

# -------------------------- Step 5: Create layer ZIP file --------------------------
echo "=== Step 5: Creating layer ZIP archive ==="
cd "${BUILD_DIR}"
zip -r "${LAYER_ZIP}" python/
mv "${LAYER_ZIP}" "../${LAYER_ZIP}"
cd - > /dev/null  # Return to original directory (silent)

# -------------------------- Step 6: Cleanup temporary files --------------------------
echo "=== Step 6: Cleaning up temporary build files ==="
rm -rf "${BUILD_DIR}"

# -------------------------- Final Output --------------------------
echo "=== Build Complete ==="
echo "Layer file created at: ${LAYER_DIR}/${LAYER_ZIP}"
echo "✅ Ready to deploy with Terraform!"

# Verify file exists
if [ -f "${LAYER_DIR}/${LAYER_ZIP}" ]; then
  echo "✅ Layer file verification: SUCCESS"
else
  echo "❌ Layer file verification: FAILED"
  exit 1
fi
