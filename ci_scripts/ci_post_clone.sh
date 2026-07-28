#!/bin/sh

# Generate the untracked Release configuration from Xcode Cloud workflow
# environment variables. Avoid printing values: the output file becomes part
# of the archive's Info.plist, while server-only credentials never belong here.
set -eu

workspace="${CI_WORKSPACE:-${CI_WORKSPACE_PATH:-$(pwd)}}"
configuration_directory="$workspace/Configuration"
output_file="$configuration_directory/Cloud.xcconfig"

required_value() {
  variable_name="$1"
  eval "variable_value=\${$variable_name-}"

  if [ -z "$variable_value" ]; then
    printf '%s\n' "Missing required Xcode Cloud environment variable: $variable_name" >&2
    exit 1
  fi

  printf '%s' "$variable_value"
}

supabase_url="$(required_value VOWBASE_PRODUCTION_SUPABASE_URL)"
publishable_key="$(required_value VOWBASE_PRODUCTION_SUPABASE_PUBLISHABLE_KEY)"
api_url="$(required_value VOWBASE_PRODUCTION_API_URL)"

mkdir -p "$configuration_directory"
umask 077
temporary_file="$(mktemp "$configuration_directory/Cloud.xcconfig.XXXXXX")"

printf '%s\n' \
  "VOWBASE_PRODUCTION_SUPABASE_URL = $supabase_url" \
  "VOWBASE_PRODUCTION_SUPABASE_PUBLISHABLE_KEY = $publishable_key" \
  "VOWBASE_PRODUCTION_API_URL = $api_url" > "$temporary_file"

mv "$temporary_file" "$output_file"
