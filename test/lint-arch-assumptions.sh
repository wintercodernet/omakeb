#!/bin/bash
# D9: no script may branch on a hardcoded architecture name.
#
# Two sanctioned exceptions, both narrow:
#
#   lib/arch.sh      — detection and dpkg->vendor name mapping is its whole job.
#   apps/*.sh        — ONLY two forms:
#                        app_archs=...            what upstream actually ships
#                        multiarch_enable <arch>  a foreign runtime a package needs
#                        arch_vendor_named a=b    what one vendor calls an arch
#                      Tier-2 repos genuinely do not exist for every architecture
#                      and apt cannot say so before the source is added (D10;
#                      Microsoft Edge publishes an arm64 index containing zero
#                      packages). Neither form is *branching* on the host
#                      architecture, which is what D9 actually forbids — they
#                      state facts about a package. Anything else still counts.

set -uo pipefail
cd "$(dirname "$0")/.."

ARCHES='amd64|arm64|x86_64|aarch64|i386|armhf|armel|ppc64el|riscv64|s390x|mips64el'

hits=$(grep -rn --include='*.sh' -E "\b($ARCHES)\b" \
        boot.sh install.sh lib install apps bin 2>/dev/null \
      | grep -v '^lib/arch.sh:' \
      | grep -vE '^apps/[^:]+:[0-9]+:app_archs=' \
      | grep -vE '^apps/[^:]+:[0-9]+:[[:space:]]*multiarch_enable ' \
      | grep -vE '^apps/[^:]+:[0-9]+:.*arch_vendor_named ' \
      | grep -vE '^[^:]+:[0-9]+:\s*#')

if [[ -n $hits ]]; then
  echo "architecture names outside the sanctioned places:"
  echo "$hits" | sed 's/^/  /'
  echo
  echo "Detection belongs in lib/arch.sh; a tier-2 app declares support with app_archs=."
  exit 1
fi
echo "no hardcoded architecture assumptions outside lib/arch.sh and apps/ declarations"
