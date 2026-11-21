#!/usr/bin/env bash
# Instalador sem root, backup da instalação existente. Compatível com bash/fish.
set -euo pipefail
umask 077
if (( EUID == 0 )); then echo 'Não execute como root.' >&2; exit 2; fi
src=$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
script="$src/atualizador-ubuntu-debian-arch.sh"
libsrc="$src/lib/atualizar"
[[ -f $script && -d $libsrc ]] || { echo 'Arquivos do projeto incompletos.' >&2; exit 2; }
if [[ ${1:-} == --ajuda ]]; then echo 'Uso: bash instalar.sh [--verificar]'; exit 0; fi
bash -n "$script"
for f in "$libsrc"/*.sh; do bash -n "$f"; done
if [[ -f $src/SHA256SUMS ]]; then (cd "$src" && sha256sum -c SHA256SUMS) || exit 1; fi
if [[ ${1:-} == --verificar ]]; then echo 'Arquivos verificados; nenhuma instalação feita.'; exit 0; fi
[[ $# == 0 ]] || { echo 'Argumento desconhecido.' >&2; exit 2; }
bin="$HOME/.local/bin"
share="$HOME/.local/share/atualizar/3.2/lib/atualizar"
backups="$HOME/.local/share/atualizar/backups"
install -d -m 700 "$bin" "$share" "$backups"
target="$bin/atualizar"
[[ ! -L "$target" ]] || { echo 'Destino simbólico; não sobrescrever.' >&2; exit 1; }
if [[ -e $target ]]; then
    printf 'Substituir %s após backup? [s/N] ' "$target"
    read -r r || exit 1
    [[ $r == [sSyY] || $r == sim || $r == SIM ]] || exit 0
    cp -p -- "$target" "$backups/atualizar-$(date +%Y%m%d-%H%M%S)-$$.sh"
fi
for f in "$libsrc"/*.sh; do install -m 600 "$f" "$share/${f##*/}"; done
staged=$(mktemp "$bin/.atualizar-XXXXXX")
trap 'rm -f -- "$staged"' EXIT
install -m 700 "$script" "$staged"
mv -f -- "$staged" "$target"
chmod 700 "$target"
trap - EXIT
printf 'Instalado: %s\nBiblioteca: %s\n' "$target" "$share"
"$target" --versao
"$target" --distro
printf 'Se necessário, adicione ~/.local/bin ao PATH do seu shell.\n'
