#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# Return zero matches when a glob doesn't match rather than returning the glob itself
shopt -s nullglob

version_lesser_equal() {
    local first
    first="$(printf "%s\n%s" "$1" "$2" | sort --version-sort | head -n 1)"
    [ "$1" = "$first" ]
}

if [[ -f "$TRUSTIFICATION_SECRET_PATH/supported_cyclonedx_version" ]]; then
    supported_version="$(cat "$TRUSTIFICATION_SECRET_PATH/supported_cyclonedx_version")"
else
    echo "The '$TRUSTIFICATION_SECRET_NAME' secret does not set supported_cyclonedx_version, will not check SBOM versions"
    supported_version=""
fi

echo "Looking for CycloneDX SBOMs in $SBOMS_DIR"

find "$SBOMS_DIR" -type f | while read -r filepath; do
    file_relpath=$(realpath "$filepath" --relative-base="$SBOMS_DIR")
    if ! jq empty "$filepath" 2> /dev/null; then
        echo "$file_relpath: not JSON"
        continue
    fi

    if ! jq -e '.bomFormat == "CycloneDX"' "$filepath" > /dev/null; then
        echo "$file_relpath: not a CycloneDX SBOM"
        continue
    fi

    echo "Found CycloneDX SBOM: $file_relpath"
    # The 'id' of each SBOM is checksum of the original content, before (possibly)
    # downgrading the CycloneDX version. The conversion always updates some metadata
    # (timestamp, UUID), changing the checksum. To avoid duplication, use the original
    # checksum.
    sbom_id="sha256:$(sha256sum "$filepath" | cut -d ' ' -f 1)"

    # Symlink the discovered SBOMS to ${WORKDIR}/${sbom_id}.json so that subsequent steps
    # don't have to look for them again.
    sbom_path="$WORKDIR/$sbom_id.json"
    ln -s "$(realpath "$filepath")" "$sbom_path"

    if [[ -n "$supported_version" ]]; then
        sbom_version="$(jq -r ".specVersion" "$sbom_path")"

        if version_lesser_equal "$sbom_version" "$supported_version"; then
            echo "SBOM version ($sbom_version) is supported (<= $supported_version), will not convert"
        else
            echo "SBOM version ($sbom_version) is not supported, will convert to $supported_version"
            printf "%s" "$supported_version" > "${sbom_path}.convert_to_version"
        fi
    fi
done

echo "Found $(find "$WORKDIR" -name "*.json" | wc -l) CycloneDX SBOMs"

for sbom_path in "$WORKDIR"/*.json; do
    conversion_attr="${sbom_path}.convert_to_version"

    if [[ -f "$conversion_attr" ]]; then
        cdx_version="$(cat "$conversion_attr")"
        original_sbom_path="$(realpath "$sbom_path")"
        original_sbom_relpath="$(realpath "$sbom_path" --relative-base="$SBOMS_DIR")"

        echo "Converting $original_sbom_relpath to CycloneDX $cdx_version"
        syft convert "$original_sbom_path" -o "cyclonedx-json@${cdx_version}=${sbom_path}.supported_version"
    else
        # Just duplicate the symlink, the original SBOM already has a supported CDX version
        cp --no-dereference "$sbom_path" "${sbom_path}.supported_version"
    fi
done

sboms_to_upload=("$WORKDIR"/*.json)

if [[ "${#sboms_to_upload[@]}" -eq 0 ]]; then
    echo "No SBOMs to upload"
    exit 0
fi

read_required_secret_key() {
    local key="$1"
    if [[ -f "$TRUSTIFICATION_SECRET_PATH/$key" ]]; then
        cat "$TRUSTIFICATION_SECRET_PATH/$key"
    else
        echo "Missing configuration: $key" >&2
        echo "Does the '$TRUSTIFICATION_SECRET_NAME' secret exist in your namespace and contain the required keys?" >&2
        echo "Refer to the description of this Task for details." >&2

        if [[ "$FAIL_IF_TRUSTIFICATION_NOT_CONFIGURED" == "false" ]]; then
            echo "WARNING: FAIL_IF_TRUSTIFICATION_NOT_CONFIGURED=false; exiting with success" >&2
            exit 0
        else
            exit 1
        fi
    fi
}

bombastic_api_url="$(read_required_secret_key bombastic_api_url)"
oidc_issuer_url="$(read_required_secret_key oidc_issuer_url)"
oidc_client_id="$(read_required_secret_key oidc_client_id)"
oidc_client_secret="$(read_required_secret_key oidc_client_secret)"

curl_opts=(--silent --show-error --fail-with-body --retry "$HTTP_RETRIES")

# https://openid.net/specs/openid-connect-discovery-1_0.html#ProviderConfig
openid_configuration_url="${oidc_issuer_url%/}/.well-known/openid-configuration"
echo "Getting OIDC issuer configuration from $openid_configuration_url"
# https://openid.net/specs/openid-connect-discovery-1_0.html#ProviderMetadata
token_endpoint="$(curl "${curl_opts[@]}" "$openid_configuration_url" | jq -r .token_endpoint)"

for sbom_path in "${sboms_to_upload[@]}"; do
    original_sbom_relpath="$(realpath "$sbom_path" --relative-base="$SBOMS_DIR")"
    echo
    echo "--- Processing $original_sbom_relpath ---"

    echo "Getting OIDC token from $token_endpoint"
    token_response="$(
        curl "${curl_opts[@]}" \
            -u "${oidc_client_id}:${oidc_client_secret}" \
            -d "grant_type=client_credentials" \
            "$token_endpoint"
    )"
    # https://www.rfc-editor.org/rfc/rfc6749.html#section-5.1
    access_token="$(jq -r .access_token <<< "$token_response")"
    token_type="$(jq -r .token_type <<< "$token_response")"
    expires_in="$(jq -r ".expires_in // empty" <<< "$token_response")"

    retry_max_time=0 # no limit
    if [[ -n "$expires_in" ]]; then
        retry_max_time="$expires_in"
    fi

    # This sbom_id is the one created in the gather-sboms step - sha256:${checksum}
    sbom_id="$(basename -s .json "$sbom_path")"
    supported_version_of_sbom="${sbom_path}.supported_version"

    echo "Uploading SBOM to $bombastic_api_url (with id=$sbom_id)"
    # https://docs.trustification.dev/trustification/user/bombastic.html#publishing-an-sbom-doc
    curl "${curl_opts[@]}" \
        --retry-max-time "$retry_max_time" \
        -H "authorization: $token_type $access_token" \
        -H "transfer-encoding: chunked" \
        -H "content-type: application/json" \
        --data "@$supported_version_of_sbom" \
        "$bombastic_api_url/api/v1/sbom?id=$sbom_id"
done
