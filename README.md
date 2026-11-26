<p align="center">
  <img src="assets/icon.svg" alt="PipeWire AT2020 Podcast Chain Icon" width="104" height="104" />
</p>

<h1 align="center">PipeWire AT2020 Podcast Chain</h1>

<p align="center">Real-time mono PipeWire microphone processing chain tuned for the Audio-Technica AT2020.</p>

<p align="center">
  <a href="https://github.com/mjdelro/pipewire-at2020-podcast-chain/releases/latest"><img src="https://img.shields.io/github/v/release/mjdelro/pipewire-at2020-podcast-chain?style=flat-square&color=f59e0b" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/PipeWire-Audio%20DSP-2b6cb0?style=flat-square&logo=linux&logoColor=white" alt="PipeWire Audio DSP" />
  <img src="https://img.shields.io/badge/Shell-Installer-4EAA25?style=flat-square&logo=gnubash&logoColor=white" alt="Shell Installer" />
</p>

---

Creates a virtual 48 kHz mono microphone named **`AT2020 Processed`** in PipeWire, tuned for a warm, controlled podcast voice on the Audio-Technica AT2020 USB.

## Signal Chain

| Stage | Processor | Purpose |
| :--- | :--- | :--- |
| **1. Denoise** | PipeWire WebRTC AEC | Removes steady background noise (AGC and high-pass disabled) |
| **2. Gate** | LSP Gate Mono (`1.2.35`) | Gentle downward expansion (-52 dB threshold, -10 dB reduction) |
| **3. High-pass** | PipeWire biquad (`65 Hz`) | Cuts desk rumble and plosives while keeping chest tone |
| **4. Vocal EQ** | PipeWire biquads | +2.5 dB warmth (`150 Hz`), -1.25 dB mud cuts (`250` & `500 Hz`), +1.0 dB presence (`3 kHz`), +0.25 dB air (`10.5 kHz`) |
| **5. Compressor** | LSP Compressor Mono (`1.2.35`) | 3.5:1 ratio, -24 dB threshold, +11 dB makeup gain |
| **6. De-esser** | LSP De-esser Mono (`1.2.35`) | Split-band above `4 kHz`, focused at `8 kHz` (3:1 reduction) |
| **7. Limiter** | LSP Limiter Mono (`1.2.35`) | Catches isolated peaks at a `-1.5 dB` ceiling |

## Quick Install (Fedora x86_64)

```bash
git clone https://github.com/mjdelro/pipewire-at2020-podcast-chain.git
cd pipewire-at2020-podcast-chain
./install.sh
```

Or download and extract the latest archive from [Releases](https://github.com/mjdelro/pipewire-at2020-podcast-chain/releases) and run `./install.sh`.

**What the installer does:**
- Installs PipeWire, WirePlumber, and LADSPA dependencies via `dnf`
- Downloads and SHA-256 verifies LSP Plugins `1.2.35` to `/usr/local/lib64/ladspa/lsp-plugins-ladspa-1.2.35.so`
- Backs up any existing `99-input-denoising.conf`, installs the new config, and validates the PipeWire graph (automatically rolls back if anything fails)
- Restarts PipeWire, selects **`AT2020 Processed`** as the default microphone (`100%`), and sets the physical `AT2020 USB` hardware gain to **`67%`**

## Mic Placement & Gain

- Speak **10–15 cm (4–6 in)** from the mic through a pop filter, slightly off-axis to tame plosives and sibilance.
- Keep the physical `AT2020 USB` input at **67%** and `AT2020 Processed` at **100%**.
- Select **`AT2020 Processed`** as your microphone in Discord, OBS, browsers, or recording apps.
- If you hit the `-1.5 dB` limiter frequently, lower the physical AT2020 input gain slightly.

## Tweaking the Sound

Edit `~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf` (all key settings are commented inline). The most useful knobs for a different voice or room:

- **Warmth / body:** `warmth` gain at `150 Hz` and `eq250` cut at `250 Hz`
- **Loudness / punch:** `compressor` threshold and makeup gain
- **Sibilance ("s" sounds):** `deesser` threshold and `8 kHz` peak detector gain

Validate and reload after any edit:

```bash
pw-config -n pipewire.conf merge context.modules >/dev/null && \
  systemctl --user restart pipewire wireplumber pipewire-pulse
```

Check logs if something sounds off:

```bash
journalctl --user -u pipewire --since '5 minutes ago' --no-pager
```

<details>
<summary><strong>Manual installation steps</strong> (if you prefer not to run <code>install.sh</code>)</summary>

1. **Install Fedora dependencies:**
   ```bash
   sudo dnf install dnf-plugins-core pipewire pipewire-utils wireplumber lsp-plugins-ladspa 7zip curl git
   ```

2. **Install LSP Plugins `1.2.35`:**
   ```bash
   work_dir=$(mktemp -d)
   curl -fL -o "$work_dir/lsp-plugins-1.2.35-Linux-x86_64.7z" \
     https://github.com/lsp-plugins/lsp-plugins/releases/download/1.2.35/lsp-plugins-1.2.35-Linux-x86_64.7z
   7z x "$work_dir/lsp-plugins-1.2.35-Linux-x86_64.7z" -o"$work_dir"
   sudo install -Dm755 \
     "$work_dir/lsp-plugins-1.2.35-Linux-x86_64/LADSPA/lsp-plugins-ladspa.so" \
     /usr/local/lib64/ladspa/lsp-plugins-ladspa-1.2.35.so
   ```

3. **Install the config and restart PipeWire:**
   ```bash
   mkdir -p ~/.config/pipewire/pipewire.conf.d
   install -m644 99-input-denoising.conf ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf
   pw-config -n pipewire.conf merge context.modules >/dev/null
   systemctl --user restart pipewire wireplumber pipewire-pulse
   pactl set-default-source at2020_processed
   pactl set-source-volume alsa_input.usb-audio-technica____AT2020_USB-00.analog-stereo 67%
   ```

</details>

## Uninstall

```bash
rm ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf
systemctl --user restart pipewire wireplumber pipewire-pulse
```

*(If `install.sh` created a `.backup.<timestamp>` file in that directory, rename it back to `99-input-denoising.conf` before restarting PipeWire.)*
