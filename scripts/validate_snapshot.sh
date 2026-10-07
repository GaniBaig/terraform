#!/usr/bin/env bash
# validate_snapshot.sh
# Takes a Vault Raft snapshot, verifies its integrity, and uploads to Azure Blob Storage.
# Deploy on the designated backup VM with daily cron: 0 2 * * * /opt/scripts/validate_snapshot.sh
#
# Prerequisites on the VM:
#   - vault binary in PATH (or set VAULT_BIN below)
#   - az CLI authenticated via Managed Identity
#   - VAULT_ADDR and VAULT_CACERT set (or configure below)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
VAULT_BIN="${VAULT_BIN:-/vault/vault}"
VAULT_ADDR="${VAULT_ADDR:-https://vault1.dev.wc.vault.qvcdev.qvc.net:8200}"
VAULT_CACERT="${VAULT_CACERT:-/vault/1.21.0/ca.crt}"
SNAPSHOT_DIR="/backups/vault/daily"
SNAPSHOT_FILE="${SNAPSHOT_DIR}/vault_backup_$(date +%Y%m%d_%H%M%S).snap"
AZURE_CONTAINER="vault-backups"
LOG_TAG="VAULT_BACKUP"
MIN_SIZE_BYTES=1024

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
mkdir -p "$SNAPSHOT_DIR"

echo "[$LOG_TAG] Starting Vault Raft snapshot — $(date)"
echo "[$LOG_TAG] VAULT_ADDR: $VAULT_ADDR"

# ---------------------------------------------------------------------------
# Step 1: Take snapshot
# ---------------------------------------------------------------------------
"$VAULT_BIN" operator raft snapshot save "$SNAPSHOT_FILE"
echo "[$LOG_TAG] Snapshot saved to: $SNAPSHOT_FILE"

# ---------------------------------------------------------------------------
# Step 2: Validate file size (must be > 1 KB)
# ---------------------------------------------------------------------------
FILESIZE=$(stat -c%s "$SNAPSHOT_FILE" 2>/dev/null || stat -f%z "$SNAPSHOT_FILE")
if [ "$FILESIZE" -lt "$MIN_SIZE_BYTES" ]; then
    echo "[$LOG_TAG ERROR] Snapshot size ($FILESIZE bytes) is too small — aborting upload." >&2
    exit 1
fi
echo "[$LOG_TAG] Size check passed: $FILESIZE bytes"

# ---------------------------------------------------------------------------
# Step 3: Verify archive integrity (gzip or tar header)
# ---------------------------------------------------------------------------
if ! gzip -t "$SNAPSHOT_FILE" 2>/dev/null && ! tar -tf "$SNAPSHOT_FILE" &>/dev/null; then
    echo "[$LOG_TAG ERROR] Snapshot archive integrity check failed — aborting upload." >&2
    exit 1
fi
echo "[$LOG_TAG] Archive integrity verified."

# ---------------------------------------------------------------------------
# Step 4: Upload to Azure Blob Storage via Managed Identity
# ---------------------------------------------------------------------------
echo "[$LOG_TAG] Uploading to Azure Blob container: $AZURE_CONTAINER ..."
az storage blob upload \
    --container-name "$AZURE_CONTAINER" \
    --file "$SNAPSHOT_FILE" \
    --name "$(basename "$SNAPSHOT_FILE")" \
    --auth-mode login

echo "[$LOG_TAG] Upload complete: $(basename "$SNAPSHOT_FILE")"

# ---------------------------------------------------------------------------
# Step 5: Cleanup local snapshots older than 7 days
# ---------------------------------------------------------------------------
find "$SNAPSHOT_DIR" -name "*.snap" -mtime +7 -delete
echo "[$LOG_TAG] Cleaned up snapshots older than 7 days."

echo "[$LOG_TAG] Backup and verification completed successfully — $(date)"
