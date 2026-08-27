#!/usr/bin/env bash
# Pulls just the public CA certificate (never the private key) out of the
# Secret cert-manager created, so it can be distributed to anything that
# needs to trust certs this CA signs — browsers, curl, other services.
#
# Without this step: every browser/client hitting https://assets.internal.lan
# (or anything else signed by internal-ca-issuer) will show a
# "certificate not trusted" warning, because as far as any client outside
# this cluster is concerned, this CA is just some random self-signed
# authority nobody told them to trust yet.
set -euo pipefail

kubectl get secret internal-ca-key-pair -n cert-manager -o jsonpath='{.data.ca\.crt}' \
  | base64 -d > internal-ca.crt

echo "Wrote internal-ca.crt — this is the ONLY file you need to distribute."
echo "(ca.crt is the public certificate; the Secret also holds tls.key, the"
echo " CA's private signing key — that must never leave the cluster.)"
echo ""
echo "── Trust it on a Debian/Ubuntu Linux client or server ──"
echo "  sudo cp internal-ca.crt /usr/local/share/ca-certificates/betxchange-internal-ca.crt"
echo "  sudo update-ca-certificates"
echo ""
echo "── Trust it on Windows ──"
echo "  Double-click internal-ca.crt → Install Certificate → Local Machine →"
echo "  'Place all certificates in the following store' → Trusted Root"
echo "  Certification Authorities."
echo ""
echo "── Trust it on macOS ──"
echo "  open internal-ca.crt   # opens Keychain Access"
echo "  Then in Keychain Access: find 'BetXchange Internal CA' under System"
echo "  keychain, double-click it, expand Trust, set 'When using this"
echo "  certificate' to 'Always Trust'."
echo ""
echo "── Trust it in Firefox specifically (Firefox ignores the OS store) ──"
echo "  about:preferences#privacy → Certificates → View Certificates →"
echo "  Authorities → Import → select internal-ca.crt → check"
echo "  'Trust this CA to identify websites'."
echo ""
echo "Until a client does one of the above, expect a browser TLS warning —"
echo "that's expected behavior for a self-signed internal CA, not a bug in"
echo "the cluster's cert-manager setup."
