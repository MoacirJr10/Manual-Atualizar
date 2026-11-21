# Ubuntu: compartilha a base APT Debian sem chamar pacman.
# Verificações Ubuntu (faseamento/HWE) são condicionadas a DISTRO_ID=ubuntu.
source "$(dirname -- "${BASH_SOURCE[0]}")/apt.sh"
