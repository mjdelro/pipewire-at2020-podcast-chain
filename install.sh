#!/usr/bin/env bash

set -Eeuo pipefail

readonly LSP_VERSION="1.2.35"
readonly LSP_ARCHIVE="lsp-plugins-${LSP_VERSION}-Linux-x86_64.7z"
readonly LSP_URL="https://github.com/lsp-plugins/lsp-plugins/releases/download/${LSP_VERSION}/${LSP_ARCHIVE}"
readonly LSP_SHA256="4ef3b2f63b29a522fdaf3a18f879c1c85c82f0bdd1e0b3c849a5f3c4b08d2550"
readonly LSP_TARGET="/usr/local/lib64/ladspa/lsp-plugins-ladspa-${LSP_VERSION}.so"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_CONFIG="${SCRIPT_DIR}/99-input-denoising.conf"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/pipewire/pipewire.conf.d"
readonly TARGET_CONFIG="${CONFIG_DIR}/99-input-denoising.conf"

temp_dir=""
backup_path=""
had_existing_config=false

info() {
    printf '\n==> %s\n' "$*"
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${temp_dir}" && -d "${temp_dir}" ]]; then
        rm -rf -- "${temp_dir}"
    fi
}

restore_config() {
    if [[ "${had_existing_config}" == true && -n "${backup_path}" ]]; then
        cp --preserve=mode,timestamps -- "${backup_path}" "${TARGET_CONFIG}"
        printf 'Restored previous configuration from %s\n' "${backup_path}" >&2
    else
        rm -f -- "${TARGET_CONFIG}"
        printf 'Removed the new configuration because installation failed.\n' >&2
    fi
}

trap cleanup EXIT

[[ -r /etc/os-release ]] || fail "Cannot identify the operating system."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "fedora" ]] || fail "This installer currently supports Fedora only."
[[ "$(uname -m)" == "x86_64" ]] || fail "This release currently supports x86_64 only."
[[ -f "${SOURCE_CONFIG}" ]] || fail "Missing ${SOURCE_CONFIG}. Run the installer from the release bundle."
command -v sudo >/dev/null || fail "sudo is required."

info "Installing Fedora dependencies"
sudo dnf -y install \
    dnf-plugins-core \
    pipewire \
    pipewire-utils \
    wireplumber \
    lsp-plugins-ladspa \
    7zip \
    curl \
    git

info "Installing the RNNoise LADSPA plugin"
sudo dnf -y copr enable lkiesow/noise-suppression-for-voice
sudo dnf -y install ladspa-realtime-noise-suppression-plugin
[[ -f /usr/lib64/ladspa/librnnoise_ladspa.so ]] || \
    fail "RNNoise was installed, but its expected LADSPA library was not found."

info "Downloading and verifying LSP Plugins ${LSP_VERSION}"
temp_dir="$(mktemp -d)"
curl -fL --retry 3 --retry-delay 2 -o "${temp_dir}/${LSP_ARCHIVE}" "${LSP_URL}"
printf '%s  %s\n' "${LSP_SHA256}" "${temp_dir}/${LSP_ARCHIVE}" | sha256sum --check --status || \
    fail "The LSP archive checksum did not match the GitHub release digest."

7z x "${temp_dir}/${LSP_ARCHIVE}" -o"${temp_dir}" >/dev/null
readonly LSP_SOURCE="${temp_dir}/lsp-plugins-${LSP_VERSION}-Linux-x86_64/LADSPA/lsp-plugins-ladspa.so"
[[ -f "${LSP_SOURCE}" ]] || fail "The LSP LADSPA library was not present in the archive."
sudo install -Dm755 -- "${LSP_SOURCE}" "${LSP_TARGET}"

command -v analyseplugin >/dev/null || fail "analyseplugin is unavailable after installing LADSPA packages."
plugin_inventory="$(analyseplugin "${LSP_TARGET}")"
for required_plugin in gate_mono compressor_mono deesser_mono limiter_mono; do
    grep -F "plugins/ladspa/${required_plugin}" <<<"${plugin_inventory}" >/dev/null || \
        fail "The installed LSP library does not expose ${required_plugin}."
done

info "Installing the PipeWire filter-chain configuration"
mkdir -p -- "${CONFIG_DIR}"
if [[ -e "${TARGET_CONFIG}" ]]; then
    had_existing_config=true
    backup_path="${TARGET_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
    cp --preserve=mode,timestamps -- "${TARGET_CONFIG}" "${backup_path}"
    printf 'Backed up the existing configuration to %s\n' "${backup_path}"
fi
install -m644 -- "${SOURCE_CONFIG}" "${TARGET_CONFIG}"

info "Validating the merged PipeWire configuration"
if ! pw-config -n pipewire.conf merge context.modules >/dev/null; then
    restore_config
    fail "PipeWire rejected the merged configuration."
fi

info "Restarting PipeWire"
if ! systemctl --user restart pipewire pipewire-pulse; then
    restore_config
    systemctl --user restart pipewire pipewire-pulse || true
    fail "PipeWire failed to restart; the previous configuration was restored."
fi

sleep 2
if ! systemctl --user is-active --quiet pipewire pipewire-pulse; then
    restore_config
    systemctl --user restart pipewire pipewire-pulse || true
    fail "PipeWire did not remain active; the previous configuration was restored."
fi

if ! pw-cli ls Node 2>/dev/null | grep -F 'AT2020 Processed' >/dev/null; then
    restore_config
    systemctl --user restart pipewire pipewire-pulse || true
    fail "The AT2020 Processed source was not created; the previous configuration was restored."
fi

info "Installation complete"
printf 'Select "AT2020 Processed" as the microphone in your application.\n'
if [[ -n "${backup_path}" ]]; then
    printf 'Previous configuration backup: %s\n' "${backup_path}"
fi
