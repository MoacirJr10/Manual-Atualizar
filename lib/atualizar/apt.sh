# Backend APT para Debian/Ubuntu. Somente este módulo usa dpkg/apt-get.
# Carregado explicitamente pela distribuição detectada em /etc/os-release.
apt_cmd=(apt-get -o DPkg::Lock::Timeout=60 -o APT::Get::Assume-Yes=false -o APT::Get::Assume-No=false)
apt_rede=(-o Acquire::Retries=2 -o Acquire::http::Timeout=25 -o Acquire::https::Timeout=25)

pkg_integridade() {
    local audit rc=0
    if audit=$(timeout 30s dpkg --audit 2>&1); then
        if [[ -n $audit ]]; then printf '%s\n' "$audit"; aviso 'Pendências do dpkg; não reparar automaticamente.'; rc=1
        else echo 'dpkg --audit: sem pendências.'; fi
    else printf '%s\n' "$audit"; aviso 'Consulta dpkg --audit não concluída.'; rc=1; fi
    if ! timeout 45s apt-get -s check; then aviso 'Verificação das dependências APT falhou.'; rc=1; fi
    return "$rc"
}

pkg_inventario() {
    local fase=$1
    if ! dpkg-query -W -f='${db:Status-Status}\t${Package}:${Architecture}\t${Version}\n' \
        | awk -F '\t' '$1=="installed"{print $2 "\t" $3}' | LC_ALL=C sort >"$work/pkg.$fase"; then
        rm -f -- "$work/pkg.$fase"; aviso "Inventário APT $fase indisponível."
    fi
}

pkg_pendentes() {
    local lista pkg
    secao 'APT — pacotes pendentes e retenções'
    if lista=$(timeout 20s apt-mark showhold); then printf 'Retidos manualmente:\n%s\n' "${lista:-Nenhum.}"; else aviso 'apt-mark indisponível.'; fi
    if existe apt && lista=$(LC_ALL=C timeout 25s apt list --upgradable 2>/dev/null); then
        lista=$(printf '%s\n' "$lista" | awk '/\[upgradable from:/')
        printf 'Pendentes nos índices locais:\n%s\n' "${lista:-Nenhum.}"
        if [[ $DISTRO_ID == ubuntu && -n $lista ]]; then
            echo 'Ubuntu — política de faseamento dos primeiros 30 pacotes:'
            while IFS= read -r pkg; do
                [[ -n $pkg ]] || continue
                LC_ALL=C timeout 8s apt-cache policy "$pkg" | grep -E '^[^[:space:]]|Installed:|Candidate:|phased' || :
            done < <(printf '%s\n' "$lista" | cut -d/ -f1 | head -n30)
        fi
        echo 'Lista de candidatos não significa, por si só, falha ou retenção manual.'
    else aviso 'Listagem APT indisponível.'; fi
}

pkg_simular() {
    secao 'APT — simulação local sem remoções'
    if ! timeout 90s "${apt_cmd[@]}" -s --no-remove dist-upgrade; then
        aviso 'Simulação APT não concluída; conferir conflitos ou remoções propostas.'; return 1
    fi
    return 0
}

pkg_atualizar() {
    local rc=0
    if ! etapa 'APT — atualizar índices' sudo "${apt_cmd[@]}" "${apt_rede[@]}" -o APT::Update::Error-Mode=any update; then
        pular 'APT — upgrade (falha no update)'; return 1
    fi
    if ! etapa 'APT — simulação sem remoções' timeout 90s "${apt_cmd[@]}" -s --no-remove dist-upgrade; then
        pular 'APT — upgrade (prévia falhou)'; return 1
    fi
    if ! confirmar 'Autorizar atualização APT após revisar a prévia?'; then
        pular 'APT — upgrade não autorizado'; parcial=1; return 1
    fi
    if ! etapa 'APT — upgrade interativo sem remoções' sudo "${apt_cmd[@]}" "${apt_rede[@]}" --no-remove dist-upgrade; then return 1; fi
    etapa 'APT — integridade após atualização' pkg_integridade || rc=1
    return "$rc"
}

pkg_limpar() {
    if etapa 'APT — prévia de dependências órfãs' timeout 60s "${apt_cmd[@]}" -s autoremove; then
        if confirmar 'Autorizar a remoção dos pacotes órfãos listados?'; then
            etapa 'APT — autoremove interativo' sudo "${apt_cmd[@]}" autoremove || :
            etapa 'APT — integridade após limpeza' pkg_integridade || :
        else pular 'APT — autoremove não autorizado'; fi
    fi
    if confirmar 'Limpar o cache de pacotes APT?'; then etapa 'APT — limpar cache' sudo "${apt_cmd[@]}" clean || :; else pular 'APT — cache preservado'; fi
}

pkg_recuperar() {
    secao 'APT — recuperação (com confirmação)'
    if (( !sudo_ok )); then aviso 'Recuperação APT exige sudo.'; falhou=1; return 1; fi
    if confirmar 'Executar dpkg --configure -a? Pode reiniciar serviços'; then
        etapa 'APT — configurar pacotes pendentes' sudo dpkg --configure -a || :
    else pular 'APT — reconfiguração não autorizada'; fi
    (( interrompido )) && return 0
    if etapa 'APT — prévia de reparo sem remoções' timeout 90s "${apt_cmd[@]}" -s --no-remove -f install; then
        if confirmar 'Autorizar apt-get -f install sem remoções?'; then
            etapa 'APT — reparar dependências' sudo "${apt_cmd[@]}" --no-remove -f install || :
        else pular 'APT — reparo não autorizado'; fi
    else aviso 'Prévia de reparo falhou; reparo não executado.'; fi
    etapa 'APT — integridade final' pkg_integridade || :
}

pkg_kernel() {
    secao 'Kernel e firmware — APT'
    local nomes
    if nomes=$(dpkg-query -W -f='${db:Status-Status}\t${Package}\t${Version}\n' 2>/dev/null); then
        nomes=$(printf '%s\n' "$nomes" | awk -F '\t' '$1=="installed" && $2~/^linux-(image-(amd64|generic|rt-amd64|cloud-amd64|[0-9])|headers-(amd64|generic)|generic|oem|virtual|lowlatency)(-|$)/ {print $2 "\t" $3}')
        printf '%s\n' "${nomes:-Nenhum pacote de kernel reconhecido no filtro; confirme a família manualmente.}"
        if [[ -n $nomes ]]; then achado NORMAL 'Pacotes de kernel Debian/Ubuntu reconhecidos; presença do metapacote deve ser confirmada caso a caso.'; fi
    else achado ATENÇÃO 'Inventário do kernel APT indisponível.'; fi
    echo 'Metapacotes marcados como manuais:'; apt-mark showmanual | grep -E '^linux-' || :
    df -h /boot /boot/efi 2>/dev/null || :
    if [[ $DISTRO_ID == ubuntu ]]; then
        echo 'Ubuntu — firmware e microcode:'
        LC_ALL=C timeout 15s apt-cache policy linux-firmware linux-firmware-amd-graphics amd64-microcode || :
    else
        echo 'Debian — firmware e microcode (sem inferir que um pacote não instalado é obrigatório):'
        LC_ALL=C timeout 15s apt-cache policy firmware-linux firmware-amd-graphics amd64-microcode intel-microcode || :
    fi
}

pkg_seguranca() {
    secao 'APT — pacotes de segurança publicados nos índices locais (indicativo)'
    if existe apt; then LC_ALL=C apt list --upgradable 2>/dev/null | grep -E -- '-security([,/[:space:]]|$)' || echo 'Nenhum candidato encontrado por este filtro; não equivale a ausência de vulnerabilidades.'; fi
    if existe systemctl; then consulta systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager; fi
}

pkg_requisitos() {
    local cmd
    for cmd in dpkg dpkg-query apt-get apt-mark; do existe "$cmd" || { echo "APT: comando essencial ausente: $cmd"; return 1; }; done
}
