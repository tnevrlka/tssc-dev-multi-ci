#!/bin/bash
set -o errexit -o nounset -o pipefail

# Run a script in the azure-cli container to set Azure variables.
# See the header in hack/_azure-set-vars.sh for more details.

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

# Find available versions with
# curl https://mcr.microsoft.com/v2/azure-cli/tags/list | jq -r '.tags[]' | sort --version-sort
: "${AZURE_CLI_IMAGE=mcr.microsoft.com/azure-cli:2.69.0}"

podman_extra_args=("$@")

# Mount volumes with SELinux label if necessary
if command -v getenforce > /dev/null && [[ "$(getenforce)" == Enforcing ]]; then
    z=":z"
else
    z=""
fi

podman run --rm -ti \
    --env 'AZURE_*' \
    --env 'ROX_*' \
    --env 'GITOPS_*' \
    --env 'QUAY_*' \
    --env 'COSIGN_*' \
    --env 'TRUSTIFICATION_*' \
    -v "$SCRIPTDIR/_azure-set-vars.sh:/tmp/_azure-set-vars.sh$z" \
    "${podman_extra_args[@]}" \
    "$AZURE_CLI_IMAGE" \
    bash /tmp/_azure-set-vars.sh
