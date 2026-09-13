#!/usr/bin/env bash
set -euo pipefail

# Bridge the refreshable `aws login` session to SDKs and tools that only understand
# the standard AWS credential_process profile setting.

AWS_DEV_AUTH_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
AWS_DEV_AUTH_LOGIN_PROFILE="${AWS_LOGIN_PROFILE:-default}"
AWS_DEV_AUTH_PROCESS_PROFILE="${AWS_PROCESS_PROFILE:-agent-login}"

die() {
  printf 'aws-dev-auth: %s\n' "$1" >&2
  return 1
}

resolve_aws_cli() {
  if [[ -n "${AWS_CLI_COMMAND:-}" ]]; then
    printf '%s\n' "$AWS_CLI_COMMAND"
    return 0
  fi

  local aws_command
  aws_command="$(command -v aws || true)"
  if [[ "$aws_command" == "/snap/bin/aws" && -x "/snap/aws-cli/current/bin/aws" ]]; then
    printf '%s\n' "/snap/aws-cli/current/bin/aws"
  elif [[ -n "$aws_command" ]]; then
    printf '%s\n' "$aws_command"
  else
    die 'aws CLI was not found on PATH'
  fi
}

AWS_DEV_AUTH_CLI="$(resolve_aws_cli)"
AWS_DEV_AUTH_CREDENTIAL_PROCESS="$AWS_DEV_AUTH_CLI configure export-credentials --profile $AWS_DEV_AUTH_LOGIN_PROFILE --format process"

setup_profile() {
  [[ "$AWS_DEV_AUTH_LOGIN_PROFILE" != "$AWS_DEV_AUTH_PROCESS_PROFILE" ]] \
    || die "AWS_LOGIN_PROFILE and AWS_PROCESS_PROFILE must be different"

  local region
  region="$("$AWS_DEV_AUTH_CLI" configure get region --profile "$AWS_DEV_AUTH_LOGIN_PROFILE" 2>/dev/null || true)"
  [[ -n "$region" ]] || region="${AWS_REGION:-ap-south-1}"

  "$AWS_DEV_AUTH_CLI" configure set credential_process "$AWS_DEV_AUTH_CREDENTIAL_PROCESS" --profile "$AWS_DEV_AUTH_PROCESS_PROFILE"
  "$AWS_DEV_AUTH_CLI" configure set region "$region" --profile "$AWS_DEV_AUTH_PROCESS_PROFILE"

  printf 'Configured AWS profile "%s" to refresh credentials from "%s".\n' \
    "$AWS_DEV_AUTH_PROCESS_PROFILE" "$AWS_DEV_AUTH_LOGIN_PROFILE"
}

source_environment() {
  export AWS_PROFILE="$AWS_DEV_AUTH_PROCESS_PROFILE"
  export AWS_CREDENTIAL_PROCESS="$AWS_DEV_AUTH_CREDENTIAL_PROCESS"

  # Keep the login source profile intact even though AWS_PROFILE points at the
  # process profile for normal CLI, SDK, Terraform, and test commands.
  aws_dev_login() {
    env -u AWS_PROFILE "$AWS_DEV_AUTH_CLI" login --profile "$AWS_DEV_AUTH_LOGIN_PROFILE" "$@"
  }
}

install_shell_hook() {
  local shell_rc="${AWS_SHELL_RC:-}"
  local shell_rcs=()
  if [[ -n "$shell_rc" ]]; then
    shell_rcs=("$shell_rc")
  else
    case "${SHELL:-}" in
      */zsh)
        shell_rcs=("$HOME/.zshrc")
        ;;
      *)
        shell_rcs=("$HOME/.bashrc")
        if [[ -f "$HOME/.bash_profile" ]]; then
          shell_rcs+=("$HOME/.bash_profile")
        fi
        ;;
    esac
  fi

  local hook="source \"$AWS_DEV_AUTH_SCRIPT_PATH\""
  local target
  for target in "${shell_rcs[@]}"; do
    if [[ ! -f "$target" ]] || ! grep -Fqx "$hook" "$target"; then
      printf '\n# Use AWS login credentials with automatic refresh for local tools.\n%s\n' "$hook" >> "$target"
    fi
    printf 'Installed AWS refresh hook in %s.\n' "$target"
  done
  printf 'Open a new shell or source its startup file.\n'
}

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/aws-dev-auth.sh setup    Configure the refreshable process profile.
  scripts/aws-dev-auth.sh install  Configure the profile and source it from the shell rc file.

When sourced, the script exports AWS_PROFILE=agent-login and defines aws_dev_login.
Use aws_dev_login to renew the underlying default login session without overwriting
the process profile.
USAGE
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  source_environment
  return 0
fi

case "${1:-}" in
  setup)
    setup_profile
    ;;
  install)
    setup_profile
    install_shell_hook
    ;;
  *)
    usage
    exit 2
    ;;
esac
