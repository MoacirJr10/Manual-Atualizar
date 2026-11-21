# Arch Linux: backend exclusivamente pacman. Não executa apt/dpkg.
# Não sincronizar DB sem upgrade: atualizações parciais não são suportadas no Arch.

pkg_requisitos() { existe pacman || { echo 'Arch: pacman indisponível.'; return 1; }; }

pkg_integridade() {
    secao 'Pacman — consistência das dependências locais'
    if timeout 45s pacman -Dk; then echo 'pacman -Dk: verificação concluída.'; return 0
    else aviso 'pacman -Dk reportou inconsistências ou não terminou.'; return 1; fi
}

pkg_inventario() {
    local fase=$1
    if ! LC_ALL=C timeout 45s pacman -Q | LC_ALL=C sort >"$work/pkg.$fase"; then
        rm -f -- "$work/pkg.$fase"; aviso "Inventário pacman $fase indisponível."
    fi
}

pkg_pendentes() {
    local rc=0 out
    secao 'Pacman — atualizações, órfãos e pacotes externos'
    if existe checkupdates; then
        # checkupdates usa banco separado e não toca a base de sync ativa do pacman.
        if out=$(LC_ALL=C timeout 75s checkupdates 2>&1); then
            printf 'Atualizações encontradas (checkupdates):\n%s\n' "${out:-Nenhuma.}"
        else
            rc=$?; if (( rc == 2 )) && [[ -z $out ]]; then echo 'checkupdates: nenhuma atualização.'
            else printf '%s\n' "$out"; aviso "checkupdates retornou código $rc; dados podem estar incompletos."; fi
        fi
    else
        echo 'checkupdates não instalado: versão local dos índices (possivelmente defasada).'
        if out=$(LC_ALL=C timeout 25s pacman -Qu 2>&1); then printf '%s\n' "${out:-Nenhuma.}"; else echo 'pacman -Qu: nenhuma atualização nos índices locais ou consulta indisponível.'; fi
    fi
    echo 'Pacotes externos/AUR (inventário apenas; nunca atualizar automaticamente):'
    timeout 25s pacman -Qm || :
    echo 'Pacotes órfãos (inventário apenas):'
    timeout 25s pacman -Qdt || :
    echo 'Para Arch, leia os avisos em archlinux.org antes de uma atualização completa.'
}

pkg_simular() {
    secao 'Arch — consulta de atualizações sem alterar bancos de pacotes'
    pkg_pendentes
    echo 'Não executar pacman -Sy isoladamente. Não é simulação de transação completa.'
    return 0
}

pkg_atualizar() {
    secao 'Arch — atualização completa (rolling release)'
    echo 'Somente pacotes oficiais. Leia os avisos em https://archlinux.org/news/ antes de continuar.'
    echo 'ATENÇÃO: pacman -Syu pode substituir kernel, bibliotecas e reiniciar serviços; sem suporte a atualização parcial.'
    if ! confirmar 'Autorizar sudo pacman -Syu (sync + upgrade completo)?'; then
        pular 'Arch — pacman -Syu não autorizado'; parcial=1; return 1
    fi
    if ! etapa 'Arch — atualização completa oficial (pacman -Syu)' sudo pacman -Syu; then return 1; fi
    etapa 'Arch — integridade das dependências pós-atualização' pkg_integridade || return 1
}

pkg_limpar() {
    local orfaos=() p
    secao 'Arch — limpeza opcional e segura'
    if ! existe pacman; then return 1; fi
    while IFS= read -r p; do [[ -z $p ]] || orfaos+=("$p"); done < <(pacman -Qdtq 2>/dev/null || :)
    if ((${#orfaos[@]})); then
        printf 'Pacotes órfãos (%s):\n' "${#orfaos[@]}"; printf '  %s\n' "${orfaos[@]}"
        if confirmar 'Remover SOMENTE os órfãos listados com pacman -Rns?'; then
            etapa 'Arch — remover órfãos listados' sudo pacman -Rns -- "${orfaos[@]}" || :
        else pular 'Arch — órfãos mantidos'; fi
    else echo 'Nenhum órfão identificado; nada a remover.'; fi
    if existe paccache; then
        if confirmar 'Reduzir cache pacman mantendo as 2 últimas versões por pacote?'; then
            etapa 'Arch — paccache -rk2' sudo paccache -r -k 2 || :
        else pular 'Arch — cache pacman mantido'; fi
    else echo 'paccache (pacman-contrib) ausente; cache preservado.'; fi
    echo 'Pacotes AUR/externos não foram removidos ou atualizados automaticamente.'
}

pkg_recuperar() {
    secao 'Arch — recuperação: somente diagnóstico (sem alteração)'
    echo 'Não existe equivalente seguro e universal ao apt-get -f install no pacman.'
    echo 'Diagnóstico local; correção manual baseada na saída e na ArchWiki.'
    pkg_integridade || :
    echo 'Pacotes com arquivos locais possivelmente ausentes:'
    timeout 90s pacman -Qk 2>&1 | tail -n 60 || :
    echo 'Revise arquivos .pacnew/.pacsave manualmente; nenhum comando de reparo automático.'
}

pkg_kernel() {
    secao 'Arch — kernels, pacotes DKMS e firmware'
    local out
    if out=$(timeout 35s pacman -Q 2>&1); then
        printf '%s\n' "$out" | grep -E '^(linux($|-lts|-zen|-hardened|-headers|-firmware|-firmware-)|dkms |(amd|intel)-ucode )' || echo 'Nenhum pacote correspondente ao filtro; verifique kernel personalizado.'
    else aviso 'Inventário de kernels Arch indisponível.'; fi
    echo 'O Arch não utiliza os metapacotes linux-generic/HWE do Ubuntu.'
    df -h /boot /efi /boot/efi 2>/dev/null || :
}

pkg_seguranca() {
    secao 'Pacman — informações de segurança e integridade'
    echo 'Sem apt-daily e sem consulta a repositórios Debian/Ubuntu.'
    echo 'Antes de atualizar: https://archlinux.org/news/'
    echo 'Pacotes externos à base oficial (possíveis AUR):'
    timeout 30s pacman -Qm || :
}
