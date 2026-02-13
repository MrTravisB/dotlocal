# Fonts

This directory is gitignored. Fonts must be installed manually.

## Required Fonts

### Berkeley Mono (Paid)
- **License**: Commercial (paid)
- **Source**: https://berkeleygraphics.com/typefaces/berkeley-mono/
- **Installation**: Purchase and download, then copy .ttf/.otf files to `fonts/BerkeleyMono/`

### Input Mono (Free for personal use)
- **License**: Free for personal use, paid for commercial
- **Source**: https://input.djr.com/
- **Installation**: Download and copy files to `fonts/InputMono/`

### Fira Code (Open Source)
- **License**: SIL Open Font License 1.1
- **Source**: https://github.com/tonsky/FiraCode
- **Installation**: `brew install --cask font-fira-code` or download from GitHub

## How fonts are installed

The `install.sh` script copies fonts from `fonts/` to `~/Library/Fonts/`. Since this directory is gitignored, you need to populate it manually before running install.
