#!/bin/bash
set -o errexit -o pipefail

# Create a variable group called $AZURE_VARIABLE_GROUP_NAME (if it doesn't exist)
# and set all the variables needed for the RHTAP pipeline.
#
# If you have the Azure CLI (az) installed and don't mind running the commands
# in this script on your machine, you can execute this script directly. Otherwise,
# run this in a container via hack/azure-set-vars.sh
#
# Before running this script, source your .env or .envrc file.

: "${AZURE_DEVOPS_EXT_PAT:?}" # the 'az' commands use this variable automatically
: "${AZURE_VARIABLE_GROUP_NAME:?}"
: "${AZURE_ORGANIZATION:?}"
: "${AZURE_PROJECT:?}"

# Set xtrace after checking variables to avoid logging the PAT
set -o xtrace

# Needed for Azure Pipelines related functionality
az extension add --name azure-devops

az devops configure --defaults \
    organization="https://dev.azure.com/$AZURE_ORGANIZATION" \
    project="$AZURE_PROJECT"

get_or_create_vargroup() {
    local group_name=$1

    local group_id
    group_id=$(
        az pipelines variable-group list --group-name "$group_name" --query '[0].id'
    )

    if [[ -z $group_id ]]; then
        group_id=$(
            az pipelines variable-group create \
                --name "$group_name" \
                --variables unused="need at least one variable in group" \
                --authorize true \
                --query id
        )
    fi

    echo "$group_id"
}

VARGROUP_ID=$(get_or_create_vargroup "$AZURE_VARIABLE_GROUP_NAME")
if [[ -z $VARGROUP_ID ]]; then
    echo "Variable group creation sometimes fails despite succeeding, trying again..." >&2
    VARGROUP_ID=$(get_or_create_vargroup "$AZURE_VARIABLE_GROUP_NAME")
fi

set_var() {
    local name=$1
    local value=$2
    local secret=${3:-true}

    if [[ -z "$value" ]]; then
        # Can't set empty values via the az CLI :/
        value=none
    fi

    local args=(--group-id "${VARGROUP_ID:?}" --name "$name" --value "$value" --secret "$secret")

    if ! az pipelines variable-group variable update "${args[@]}"; then
        echo "Creating a new variable..." >&2
        az pipelines variable-group variable create "${args[@]}"
    fi
}

# Don't log secrets
set +o xtrace

set_var ROX_CENTRAL_ENDPOINT "$ROX_CENTRAL_ENDPOINT" false
set_var ROX_API_TOKEN "$ROX_API_TOKEN"

set_var GITOPS_AUTH_PASSWORD "$GITOPS_AUTH_PASSWORD"

set_var QUAY_IO_CREDS_USR "$QUAY_IO_CREDS_USR" false
set_var QUAY_IO_CREDS_PSW "$QUAY_IO_CREDS_PSW"

set_var COSIGN_SECRET_PASSWORD "$COSIGN_SECRET_PASSWORD"
set_var COSIGN_SECRET_KEY "$COSIGN_SECRET_KEY"
set_var COSIGN_PUBLIC_KEY "$COSIGN_PUBLIC_KEY" false

set_var TRUSTIFICATION_BOMBASTIC_API_URL "$TRUSTIFICATION_BOMBASTIC_API_URL" false
set_var TRUSTIFICATION_OIDC_ISSUER_URL "$TRUSTIFICATION_OIDC_ISSUER_URL" false
set_var TRUSTIFICATION_OIDC_CLIENT_ID "$TRUSTIFICATION_OIDC_CLIENT_ID" false
set_var TRUSTIFICATION_OIDC_CLIENT_SECRET "$TRUSTIFICATION_OIDC_CLIENT_SECRET"
set_var TRUSTIFICATION_SUPPORTED_CYCLONEDX_VERSION "$TRUSTIFICATION_SUPPORTED_CYCLONEDX_VERSION" false
