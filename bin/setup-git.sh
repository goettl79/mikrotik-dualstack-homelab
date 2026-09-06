#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] Setting up Git hooks and SOPS diff configuration..."

# 1. Enable custom Git hooks in .githooks
git -C "${SCRIPT_DIR}" config core.hooksPath .githooks
chmod +x "${SCRIPT_DIR}/.githooks/"* "${SCRIPT_DIR}/bin/"*

# 2. Configure Git alias for scommit
git -C "${SCRIPT_DIR}" config alias.scommit '!./bin/commit.sh'

# 3. Configure readable git diff for encrypted files
git -C "${SCRIPT_DIR}" config diff.sops.textconv "sops -d"
git -C "${SCRIPT_DIR}" config diff.sops-binary.textconv "sops -d --input-type binary --output-type binary"

# 4. Decrypt local plaintext working files if age key is present
if [[ -f "${HOME}/.config/sops/age/keys.txt" ]]; then
    echo "[*] Decrypting local working files..."
    "${SCRIPT_DIR}/bin/decrypt.sh"
fi

echo "[+] Git hooks and SOPS configuration successfully installed!"
echo "    - 'inventory.yaml' and 'setup.rsc' are now ready to read and edit locally."
echo "    - 'git scommit' or './bin/commit.sh' will automatically encrypt modified files before committing."
echo "    - 'pre-commit' hook guards against accidental leaks of plaintext files."
echo "    - 'post-merge' and 'post-checkout' hooks will automatically decrypt updated secrets."
echo "    - 'git diff' will display readable plaintext diffs."

