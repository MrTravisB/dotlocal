# Fonts

Fonts are encrypted in this repository using `age` encryption and stored as `fonts.tar.gz.age`. The decryption key is stored in 1Password.

## How Fonts Are Installed

The `install.sh` script automatically:

1. Installs 1Password, 1Password CLI, and `age` via Homebrew
2. Prompts you to sign into 1Password (if not already signed in)
3. Retrieves the decryption key from 1Password (`op://Personal/dotlocal-fonts-key/notes`)
4. Decrypts `fonts.tar.gz.age` into the `fonts/` directory
5. Copies fonts from `fonts/` to `~/Library/Fonts/`

No manual font installation is required on new machines.

## One-Time Setup (Already Complete)

The following steps were completed during initial setup. You only need to repeat them if fonts change:

### 1. Generate Age Keypair

```bash
age-keygen -o fonts.age
```

This creates a key file with:
- A private key (secret key starting with `AGE-SECRET-KEY-`)
- A public key (recipient starting with `age1`)

### 2. Store Private Key in 1Password

1. Open 1Password
2. Create a new Secure Note in the "Personal" vault
3. Name it: `dotlocal-fonts-key`
4. Paste the entire contents of `fonts.age` into the notes field
5. Save the item

### 3. Encrypt Fonts

```bash
# From the repo root
tar czf - fonts/ | age -r <PUBLIC_KEY> > fonts.tar.gz.age
```

Replace `<PUBLIC_KEY>` with the public key from step 1 (the `age1...` string).

### 4. Commit Encrypted Archive

```bash
git add fonts.tar.gz.age
git commit -m "Add encrypted fonts archive"
git push
```

## Re-Encrypting When Fonts Change

If you add or update fonts in the `fonts/` directory:

```bash
# Retrieve the public key from 1Password
op read "op://Personal/dotlocal-fonts-key/public_key"

# Or extract it from the private key
grep "public key:" fonts.age

# Re-encrypt
tar czf - fonts/ | age -r <PUBLIC_KEY> > fonts.tar.gz.age

# Commit
git add fonts.tar.gz.age
git commit -m "Update encrypted fonts"
git push
```

## Required Fonts (Reference)

These fonts are included in the encrypted archive:

### Berkeley Mono (Paid)
- **License**: Commercial (paid)
- **Source**: https://berkeleygraphics.com/typefaces/berkeley-mono/

### Input Mono (Free for personal use)
- **License**: Free for personal use, paid for commercial
- **Source**: https://input.djr.com/

### Fira Code (Open Source)
- **License**: SIL Open Font License 1.1
- **Source**: https://github.com/tonsky/FiraCode
