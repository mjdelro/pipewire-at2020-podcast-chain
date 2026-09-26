# PipeWire AT2020 Podcast Chain

A real-time mono microphone processing chain for PipeWire, tuned for an
Audio-Technica AT2020 and a deep, controlled podcast sound.

The virtual source is named **AT2020 Processed** and runs at 48 kHz. The chain
contains:

1. RNNoise noise suppression without hard VAD muting
2. Gentle downward expansion
3. 65 Hz high-pass filtering
4. Vocal EQ for warmth, mud control, presence, and air
5. Voice compression
6. Split-band de-essing centered around 8 kHz
7. A -1.5 dB peak limiter

## Requirements

The included paths and commands target Fedora x86_64. Other distributions can
use the same graph, but may need to change the LADSPA library paths in
`99-input-denoising.conf`.

- PipeWire and WirePlumber
- PipeWire utilities (`pw-config`, `pw-cli`)
- RNNoise LADSPA plugin from `noise-suppression-for-voice`
- LSP LADSPA plugins
- LSP Plugins 1.2.35 for the gate, compressor, de-esser, and limiter

## Installation on Fedora

### Automated installation

Download the latest release bundle from the
[Releases page](https://github.com/mjdelro/pipewire-at2020-podcast-chain/releases),
extract it, and run:

```bash
chmod +x install.sh
./install.sh
```

The installer supports Fedora x86_64. It installs the required packages,
verifies the downloaded LSP archive against its SHA-256 release digest, backs
up an existing configuration, validates the merged PipeWire graph, activates
the virtual source, and automatically restores the previous configuration if
validation or activation fails.

To install from a Git checkout instead:

```bash
git clone https://github.com/mjdelro/pipewire-at2020-podcast-chain.git
cd pipewire-at2020-podcast-chain
./install.sh
```

The remaining sections describe the same process manually.

### 1. Install PipeWire tools and packaged plugins

```bash
sudo dnf install \
  dnf-plugins-core \
  pipewire \
  pipewire-utils \
  wireplumber \
  lsp-plugins-ladspa \
  7zip \
  curl \
  git
```

Enable the COPR containing the RNNoise LADSPA plugin, then install it:

```bash
sudo dnf copr enable lkiesow/noise-suppression-for-voice
sudo dnf install ladspa-realtime-noise-suppression-plugin
```

Confirm that RNNoise is available:

```bash
test -f /usr/lib64/ladspa/librnnoise_ladspa.so
```

### 2. Install the LSP 1.2.35 processing stack

The Fedora LSP package may not yet contain `deesser_mono`. The configuration
pins every LSP processor to the same 1.2.35 build so plugin behavior stays
consistent. Install the official LADSPA binary alongside the packaged library:

```bash
work_dir=$(mktemp -d)
curl -fL \
  -o "$work_dir/lsp-plugins-1.2.35-Linux-x86_64.7z" \
  https://github.com/lsp-plugins/lsp-plugins/releases/download/1.2.35/lsp-plugins-1.2.35-Linux-x86_64.7z
7z x "$work_dir/lsp-plugins-1.2.35-Linux-x86_64.7z" -o"$work_dir"
sudo install -Dm755 \
  "$work_dir/lsp-plugins-1.2.35-Linux-x86_64/LADSPA/lsp-plugins-ladspa.so" \
  /usr/local/lib64/ladspa/lsp-plugins-ladspa-1.2.35.so
```

Confirm that the installed library exposes the complete mono processing stack:

```bash
for plugin in gate_mono compressor_mono deesser_mono limiter_mono; do
  analyseplugin /usr/local/lib64/ladspa/lsp-plugins-ladspa-1.2.35.so \
    | grep -F "plugins/ladspa/$plugin"
done
```

### 3. Install the PipeWire configuration

Clone this repository and enter it:

```bash
git clone https://github.com/mjdelro/pipewire-at2020-podcast-chain.git
cd pipewire-at2020-podcast-chain
```

Create the PipeWire override directory and back up an existing configuration:

```bash
mkdir -p ~/.config/pipewire/pipewire.conf.d
if test -f ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf; then
  cp ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf \
    ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf.backup
fi
install -m644 99-input-denoising.conf \
  ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf
```

### 4. Validate and activate

Validate the merged PipeWire module configuration before restarting audio:

```bash
pw-config -n pipewire.conf merge context.modules >/dev/null
```

Restart PipeWire and confirm that both services return:

```bash
systemctl --user restart pipewire pipewire-pulse
systemctl --user is-active pipewire pipewire-pulse
```

Confirm that the virtual microphone exists:

```bash
pw-cli ls Node | grep -A8 -B2 'AT2020 Processed'
```

Select **AT2020 Processed** as the microphone in the recording, conferencing,
or streaming application. Keep the physical AT2020 input selected as the
capture source in the system audio routing.

## Signal level and placement

- Speak about 10-15 cm (4-6 in) from the microphone through a pop filter.
- Aim slightly off-axis to reduce plosives and sibilance.
- Set the hardware input so normal speech is healthy but never clips.
- The chain intentionally leaves RNNoise VAD at 0% to prevent syllables from
  being cut into digital silence.
- The limiter ceiling is -1.5 dB; frequent contact with that ceiling means the
  physical microphone gain is probably too high.

## Customization

The configuration contains comments next to the important controls. Make small
changes and record a representative one-minute sample before adjusting again.
For a different voice or microphone, the most useful controls are:

- `warmth` gain at 125 Hz
- the 250 Hz mud cut
- compressor threshold and makeup gain
- de-esser threshold and 8 kHz detector gain

After any edit, validate and reload:

```bash
pw-config -n pipewire.conf merge context.modules >/dev/null && \
  systemctl --user restart pipewire pipewire-pulse
```

Check for graph or plugin errors:

```bash
journalctl --user -u pipewire --since '5 minutes ago' --no-pager
```

## Removal and rollback

Remove only this override, then restart PipeWire:

```bash
rm ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf
systemctl --user restart pipewire pipewire-pulse
```

If a backup was created during installation, restore it instead:

```bash
mv ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf.backup \
  ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf
systemctl --user restart pipewire pipewire-pulse
```

## Notes

This is a real-time voice chain, not a replacement for final loudness
normalization during podcast mastering. Recording applications that duplicate a
mono source into stereo can also report approximately 3 LU more loudness than a
true mono export.
