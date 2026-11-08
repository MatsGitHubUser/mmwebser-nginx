#!/usr/bin/env bash
# One-time setup, safe to re-run. Needs `az login` (Owner on the subscription)
# and `gh auth login`. Usage: scripts/bootstrap-azure.sh OWNER/REPO
set -euo pipefail

REPO="${1:?usage: $0 OWNER/REPO}"
LOCATION="${LOCATION:-swedencentral}"
RG_APP="rg-webserver"
RG_STATE="rg-webserver-tfstate"
APP_NAME="github-azure-webserver"

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
STORAGE="tfwebserver$(printf '%s' "$SUB_ID" | sha1sum | cut -c1-8)"

echo "==> Registering resource providers"
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.Storage --wait

echo "==> Creating resource groups in $LOCATION"
RG_APP_ID="$(az group create -n "$RG_APP" -l "$LOCATION" --query id -o tsv)"
az group create -n "$RG_STATE" -l "$LOCATION" -o none

echo "==> Creating Terraform state storage: $STORAGE"
STORAGE_ID="$(az storage account create -n "$STORAGE" -g "$RG_STATE" -l "$LOCATION" \
  --sku Standard_LRS --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false \
  --query id -o tsv)"
az storage container-rm create --storage-account "$STORAGE" -n tfstate -o none

echo "==> Creating GitHub identity: $APP_NAME"
CLIENT_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
if [[ -z "$CLIENT_ID" ]]; then
  CLIENT_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
fi
SP_ID="$(az ad sp show --id "$CLIENT_ID" --query id -o tsv 2>/dev/null || true)"
if [[ -z "$SP_ID" ]]; then
  SP_ID="$(az ad sp create --id "$CLIENT_ID" --query id -o tsv)"
fi

# GitHub can include numeric owner and repo IDs in the subject, so ask it for
# the exact prefix instead of building one from the repository name.
SUB_PREFIX="$(gh api "repos/${REPO}/actions/oidc/customization/sub" --jq .sub_claim_prefix)"
: "${SUB_PREFIX:?could not read the OIDC subject prefix for $REPO from GitHub}"
SUBJECT="${SUB_PREFIX}:ref:refs/heads/main"
CRED_NAME="github-main"
CRED_PARAMS="{
  \"name\": \"${CRED_NAME}\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"${SUBJECT}\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"
EXISTING="$(az ad app federated-credential list --id "$CLIENT_ID" \
  --query "[?name=='${CRED_NAME}'] | length(@)" -o tsv)"
if [[ "$EXISTING" == "0" ]]; then
  az ad app federated-credential create --id "$CLIENT_ID" -o none --parameters "$CRED_PARAMS"
else
  az ad app federated-credential update --id "$CLIENT_ID" -o none \
    --federated-credential-id "$CRED_NAME" --parameters "$CRED_PARAMS"
fi

echo "==> Granting access (app resource group and state storage only)"
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role Contributor --scope "$RG_APP_ID" -o none
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$STORAGE_ID" -o none

echo "==> Setting GitHub repository variables on $REPO"
gh variable set AZURE_CLIENT_ID --repo "$REPO" --body "$CLIENT_ID"
gh variable set AZURE_TENANT_ID --repo "$REPO" --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$SUB_ID"
gh variable set TFSTATE_STORAGE_ACCOUNT --repo "$REPO" --body "$STORAGE"

echo "Done."
