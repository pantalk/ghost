# Image size and the graphical stack

Pantalk Ghost runs its messaging bridge and agent harnesses headlessly, but
also includes a graphical desktop. This document records why that desktop is
present, what has been trimmed, and how to measure its current cost without
letting old measurements turn into documentation folklore.

Generate the report from the current image with:

```bash
make build
make size-report
```

The report shows the largest image layers, then measures the desktop as the
dependency closure of its top-level packages. That closure answers the useful
question: how much would actually disappear if Ghost stopped being
graphical?

## Current measurement

The Ghost `0.0.11` toolchain image built on 2026-07-26 is **3.63 GB**
(3467 MiB) uncompressed. Its graphical package closure is **900 MiB, or 26.0%
of the image**:

| Component                         |     Size |
| --------------------------------- | -------: |
| Chrome                            | 413.6 MiB |
| Mesa and LLVM software GL         | 186.1 MiB |
| Fonts and icon themes             | 144.3 MiB |
| KasmVNC and its Perl dependencies |  36.1 MiB |
| Ghostscript dependency chain      |  26.3 MiB |
| GTK, Pango, and GStreamer         |  23.8 MiB |
| Kitty terminal                    |  18.8 MiB |
| X11 utilities                     |   7.7 MiB |
| Openbox, Tint2, and Picom         |   5.2 MiB |
| Ranger file manager               |   1.1 MiB |
| Other shared libraries            |  37.3 MiB |

The pinned agent CLI installation is the largest single image layer at 1.71
GB, nearly twice the entire graphical closure. Run the report again after
dependency changes rather than treating these measurements as permanent.

## Why Ghost includes a desktop

The desktop serves three concrete purposes:

1. It makes the long-lived Pantalk and harness environment inspectable. The
   terminal, logs, file manager, and browser share the same filesystem and
   process namespace as the running daemon.
2. Runtime authentication needs a browser or an interactive terminal. Keeping
   those flows inside Ghost also keeps the resulting credentials in
   Ghost's named volumes.
3. It provides the complete substrate for computer use: KasmVNC supplies the
   display, Chrome is the target application, `scrot` captures it, and
   `xdotool` and `wmctrl` provide input and window control.

Openbox, Tint2, Cortile, and the terminal are a small part of the graphical
cost. Chrome, fonts, and software GL are the substantial pieces, and they are
also what make browser login and computer use practical.

## What is trimmed

KasmVNC supplies its own X server, so Ghost does not install Ubuntu's `xorg`
metapackage or `x11-xserver-utils`. Those packages pull in a hardware display
server, drivers, keyboard configuration, udev/systemd, and compiler support
that this container cannot use.

Ghost explicitly keeps `xauth`, `xkb-data`, `x11-xkb-utils`, and
`xfonts-base`, which are needed by KasmVNC and its core font path.

## Interpreting the report

The figures are uncompressed on-disk sizes. Registry transfer sizes will be
smaller and will not preserve the same proportions because binaries, fonts,
and libraries compress differently.
