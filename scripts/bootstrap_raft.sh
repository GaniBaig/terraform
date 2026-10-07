#!/usr/bin/env bash
# bootstrap_raft.sh
# Bootstraps a 3-node Vault Raft cluster on the new ACI VMs.
#
# Run ONCE on vault-aci-01 (node_1) AFTER Ansible has deployed Vault on all 3 nodes.
# Steps:
#   1. Initialise Vault on node_1 (generates recovery keys + root token)
#   2. Join node_2 and node_3 to the Raft cluster via SSH
#   3. Verify quorum (all 3 nodes showing as voters)
#
# Prerequisites:
#   - Ansible playbook has run successfully on all 3 nodes
#   - Azure Managed Identity has Key Vault Crypto User role on the AKV
#   - TLS certs deployed at $VAULT_CACERT on each node
#   - SSH access from this machine to all 3 nodes as the vault user

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — update IPs once ACI VMs are provisioned
# ---------------------------------------------------------------------------
NODE1_IP="10.184.32.TBD1"    # vault-aci-01
NODE2_IP="10.184.32.TBD2"    # vault-aci-02
NODE3_IP="10.184.32.TBD3"    # vault-aci-03

NODE1_DNS="vault-aci-01.qvcdev.qvc.net"
NODE2_DNS="vault-aci-02.qvcdev.qvc.net"
NODE3_DNS="vault-aci-03.qvcdev.qvc.net"

VAULT_BIN="/vault/vault"
VAULT_CACERT="/vault/1.21.0/ca.crt"
VAULT_TLS_CERT="/vault/1.21.0/server.crt"
VAULT_TLS_KEY="/vault/1.21.0/server.key"
INIT_OUTPUT="/root/vault_init_output.json"

# ---------------------------------------------------------------------------
# Step 1: Initialise Vault on node_1
# ---------------------------------------------------------------------------
echo "==> Step 1: Initialising Vault on node_1 ($NODE1_IP) ..."
ssh vault@"$NODE1_IP" bash -s <<EOF
  export VAULT_ADDR="https://${NODE1_IP}:8200"
  export VAULT_CACERT="${VAULT_CACERT}"
  ${VAULT_BIN} operator init -format=json > ${INIT_OUTPUT}
  echo "Initialisation complete. Output saved to ${INIT_OUTPUT}"
  echo "==> IMPORTANT: Securely store the recovery keys and root token from ${INIT_OUTPUT}"
  echo "==> Azure KMS auto-unseal will unseal the cluster automatically."
  ${VAULT_BIN} status
EOF

# ---------------------------------------------------------------------------
# Step 2: Join node_2 to the Raft cluster
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 2: Joining node_2 ($NODE2_IP) to Raft cluster ..."
ssh vault@"$NODE2_IP" bash -s <<EOF
  export VAULT_ADDR="https://${NODE2_IP}:8200"
  export VAULT_CACERT="${VAULT_CACERT}"
  ${VAULT_BIN} operator raft join \
    -leader-ca-cert-file=${VAULT_CACERT} \
    -leader-client-cert-file=${VAULT_TLS_CERT} \
    -leader-client-key-file=${VAULT_TLS_KEY} \
    https://${NODE1_DNS}:8200
  echo "node_2 joined successfully."
EOF

# ---------------------------------------------------------------------------
# Step 3: Join node_3 to the Raft cluster
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 3: Joining node_3 ($NODE3_IP) to Raft cluster ..."
ssh vault@"$NODE3_IP" bash -s <<EOF
  export VAULT_ADDR="https://${NODE3_IP}:8200"
  export VAULT_CACERT="${VAULT_CACERT}"
  ${VAULT_BIN} operator raft join \
    -leader-ca-cert-file=${VAULT_CACERT} \
    -leader-client-cert-file=${VAULT_TLS_CERT} \
    -leader-client-key-file=${VAULT_TLS_KEY} \
    https://${NODE1_DNS}:8200
  echo "node_3 joined successfully."
EOF

# ---------------------------------------------------------------------------
# Step 4: Verify quorum — all 3 nodes showing as voters
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 4: Verifying Raft quorum on node_1 ..."
ssh vault@"$NODE1_IP" bash -s <<EOF
  export VAULT_ADDR="https://${NODE1_IP}:8200"
  export VAULT_CACERT="${VAULT_CACERT}"
  ${VAULT_BIN} operator raft list-peers
EOF

echo ""
echo "==> Bootstrap complete."
echo "    Expected: 3 nodes all showing State=follower/leader and Voter=true"
echo "    Next step: Take snapshot from existing sandbox leader (vault3 / 10.184.32.33)"
echo "    and restore onto this cluster: ${VAULT_BIN} operator raft snapshot restore -force <snapshot>"
