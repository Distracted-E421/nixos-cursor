# Certificate Pinning Bypass Techniques

When applications implement certificate pinning, they verify that the server's certificate matches a pre-defined certificate or public key. This prevents MITM proxies from intercepting traffic.

## Detection

If you see errors like:
- `SSL certificate problem`
- `certificate verify failed`
- `NET::ERR_CERT_AUTHORITY_INVALID`
- Connection resets immediately after TLS handshake

...then certificate pinning is likely in effect.

## Bypass Techniques for Electron Apps (Cursor)

### 1. Chromium Flag (Easiest) ✅ RECOMMENDED

Electron/Chromium apps respect the `--ignore-certificate-errors` flag:

```bash
cursor --ignore-certificate-errors --proxy-server=http://127.0.0.1:8080
```

**How it works**: Disables all certificate verification, including pinning.

**Risk**: Low for testing. Don't use for regular browsing.

### 2. Environment Variables

Some Electron apps respect Node.js TLS settings:

```bash
NODE_TLS_REJECT_UNAUTHORIZED=0 cursor
```

Or combined with proxy:

```bash
HTTP_PROXY=http://127.0.0.1:8080 \
HTTPS_PROXY=http://127.0.0.1:8080 \
NODE_TLS_REJECT_UNAUTHORIZED=0 \
cursor
```

### 3. System CA Trust (NixOS)

Trust mitmproxy's CA system-wide:

```nix
# configuration.nix
security.pki.certificateFiles = [
  /home/e421/.mitmproxy/mitmproxy-ca-cert.pem
];
```

Then rebuild:
```bash
sudo nixos-rebuild switch
```

**Note**: This makes ALL apps trust the CA, which is powerful but be careful.

### 4. App-Specific CA Bundle

Some apps read CA from environment:

```bash
SSL_CERT_FILE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem cursor
REQUESTS_CA_BUNDLE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem cursor
```

### 5. Electron app.asar Modification

Cursor's app code is at:
```
/nix/store/.../share/cursor/resources/app/
```

You could potentially:
1. Copy the app directory
2. Modify the TLS verification code
3. Launch with modified app path

**Not recommended**: Breaks on updates, may violate ToS.

### 6. Frida (Dynamic Instrumentation)

For heavily pinned apps, Frida can disable pinning at runtime:

```bash
nix shell nixpkgs#frida-tools

# List hooked SSL functions
frida-trace -i "SSL_*" cursor

# Use objection for automatic unpinning
pip install objection
objection -g cursor explore
> android sslpinning disable  # (concept, actual command differs)
```

**Note**: Complex, usually overkill for Electron apps.

## Testing Order

1. **Try `--ignore-certificate-errors` first** (most likely to work)
2. **Try environment variables** (if #1 fails)
3. **Trust CA system-wide** (if app ignores flags)
4. **Frida** (last resort)

## Cursor-Specific Notes

### What We Know

- Cursor is built on Electron (Chromium-based)
- Electron respects `--ignore-certificate-errors`
- Cursor's app bundle is unpacked (not asar), making inspection easy

### Expected Behavior

Most Electron apps do NOT implement custom cert pinning because:
- Chromium's TLS is already secure
- Adding pinning requires extra code
- Updates would break if certs change

### If Pinning IS Detected

Cursor would have to explicitly check certificates in their JavaScript code. Look in:
```
/nix/store/.../share/cursor/resources/app/out/
```

For patterns like:
- `checkCertificate`
- `pinnedCertificates`
- `verifyServerCertificate`
- Custom `https.Agent` with `ca` option

## Rotating Certificates

If the issue is certificate expiration/rotation (not pinning):

### mitmproxy CA Renewal

```bash
# Remove old CA
rm -rf ~/.mitmproxy

# Generate new CA
mitmdump -p 8080 &
sleep 2
kill %1

# New CA is at ~/.mitmproxy/mitmproxy-ca-cert.pem
```

### Custom CA with Longer Validity

```bash
# Generate a 10-year CA
openssl req -x509 -newkey rsa:4096 \
  -keyout ca-key.pem \
  -out ca-cert.pem \
  -days 3650 \
  -nodes \
  -subj "/CN=Cursor Proxy CA"

# Use with mitmproxy
mitmdump --certs *=ca-key.pem:ca-cert.pem
```

## Security Reminder

⚠️ **Never run a MITM proxy on production machines with untrusted traffic!**

This setup is for:
- Local development/testing
- Your own machines
- Controlled environments

The proxy can see ALL traffic, including passwords and tokens.

