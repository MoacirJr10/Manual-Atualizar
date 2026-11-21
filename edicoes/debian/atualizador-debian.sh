#!/usr/bin/env bash
# Atualizador Debian - 3.2-preview - edição independente e experimental.
set -u
set -o pipefail
umask 077
modo=atualizar; modo_explicito=0; limpeza=0; flatpak_sim=0; sem_sudo=0
self=$(readlink -f -- "${BASH_SOURCE[0]}") || exit 2
# Edição exclusiva: aborta mesmo se outro gerenciador estiver instalado.
[[ -r /etc/os-release ]] || { echo 'Arquivo /etc/os-release ausente.'; exit 2; }
DISTRO_ID=$( . /etc/os-release; printf '%s' "${ID:-unknown}" )
DISTRO_ID=${DISTRO_ID,,}
if [[ $DISTRO_ID != 'debian' ]]; then
    printf 'Este é o Atualizador Debian; sistema detectado: %s. Nenhuma ação foi executada.\n' "$DISTRO_ID" >&2
    exit 2
fi
DISTRO_LABEL='Debian'
PKG_LABEL='APT'
baixados=$(xdg-user-dir DOWNLOAD 2>/dev/null) || baixados="$HOME/Downloads"
[[ $baixados == /* && $baixados != "$HOME" ]] || baixados="$HOME/Downloads"
pasta="$baixados/Relatorios-atualizador-debian"
exportar() {
    # O HTML é local, sem scripts, fontes externas ou envio de dados.
    python3 - "$pasta" "$@" <<'PYEXPORT'
import sys, pathlib, json, re, html, os, tempfile
base=pathlib.Path(sys.argv[1]); action=sys.argv[2]
if base.is_symlink(): sys.exit('Pasta de relatórios inválida (link simbólico).')
if base.exists() and (not base.is_dir() or base.stat().st_uid!=os.getuid()): sys.exit('Pasta de relatórios inválida.')
files=sorted((p for p in base.glob('atualizacao-*.txt') if p.is_file() and not p.is_symlink()), key=lambda p:p.name, reverse=True)
def read(p):
    text=p.read_text(encoding='utf-8',errors='replace')
    summary=text.rsplit('===== RESUMO FINAL =====',1)
    tail=summary[1] if len(summary)==2 else ''
    def line(prefix):
        return next((l[len(prefix):].strip() for l in tail.splitlines() if l.startswith(prefix)),None)
    blocks=tail.split('Avisos registrados:',1)
    steps=[l.strip()[2:] for l in blocks[0].splitlines() if l.strip().startswith('• ')]
    warnings=[]
    if len(blocks)==2:
        for l in blocks[1].splitlines()[1:]:
            if not l.strip().startswith('• '): break
            warnings.append(l.strip()[2:])
    def lastnum(pattern):
        q=re.findall(pattern,text,re.M); return int(q[-1].replace(',','').replace('.','')) if q else None
    metrics={ 'smart_desgaste_pct':lastnum(r'^Percentage Used:\s+(\d+)%'), 'smart_desligamentos_inseguros':lastnum(r'^Unsafe Shutdowns:\s+([\d,.]+)'), 'smart_erros_midia':lastnum(r'^Media and Data Integrity Errors:\s+([\d,.]+)') }
    if len(re.findall(r'^Percentage Used:',text,re.M))>1:
        metrics={k:None for k in metrics}
    achados=[]
    matching=re.search(r'^Achados classificados: \d+\n((?:  • .*\n)*)',tail,re.M)
    if matching:
        for entry in matching[1].splitlines():
            m=re.match(r'  • \[([^]]+)\] (.*)',entry)
            if m: achados.append(dict(nivel=m[1],mensagem=m[2]))
    for w in warnings:
        if not re.match(r'^\[(CRÍTICO|ATENÇÃO|INFORMATIVO|NORMAL)\] ',w):
            achados.append(dict(nivel='ATENÇÃO',mensagem=w))
    extra={}
    for k,v in re.findall(r'^METRICA: ([a-z0-9_]+)=([^\n]+)',text,re.M):
        try: extra[k]=float(v) if '.' in v else int(v)
        except ValueError: extra[k]=v
    return text,dict(achados=achados,metricas=extra,arquivo=p.name,inicio=text.splitlines()[0] if text else '',fim=line('Fim:'),resultado=line('Resultado:') or 'Relatório sem resumo 3.x/2.x (ou incompleto)',etapas=steps,avisos=warnings,reinicio=line('Reinício:'),**metrics)
def write(path, data):
    fd,tmp=tempfile.mkstemp(dir=path.parent,prefix='.export-')
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as f: f.write(data)
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
if action=='historico':
    if not files: print('Nenhum relatório encontrado.');sys.exit(0)
    for p in files[:15]:
        _,d=read(p); print(f"{p.name} | {d['resultado']} | avisos: {len(d['avisos']) if d['fim'] else '?'}")
    sys.exit(0)
if len(sys.argv)>3:
    p=pathlib.Path(sys.argv[3]);
    if p.parent.resolve()!=base.resolve() or not p.is_file() or p.is_symlink(): sys.exit('Relatório inválido.')
else:
    if not files: sys.exit('Nenhum relatório encontrado.')
    p=next((q for q in files if read(q)[1]['fim']),None)
    if p is None: sys.exit('Nenhum relatório finalizado encontrado.')
text,d=read(p)
if action=='comparar':
    def mode(info):
        m=re.search(r'Modo: (\w+)',info['inicio']); return m.group(1) if m else None
    previous=next((q for q in files if q.name<p.name and read(q)[1]['fim'] and mode(read(q)[1])==mode(d) and mode(d)),None)
    if previous is None or not d['fim']:
        if len(sys.argv)==3: print('Nenhum relatório anterior finalizado do mesmo modo.')
        sys.exit(0)
    _,old=read(previous)
    a,b=set(old['avisos']),set(d['avisos'])
    print('Comparação com '+previous.name+':')
    print('  Novos avisos: '+('; '.join(sorted(b-a)) or 'nenhum'))
    print('  Avisos não repetidos (não implica resolução): '+('; '.join(sorted(a-b)) or 'nenhum'))
    print('  Avisos recorrentes: '+str(len(a&b)))
    for k in ('soc_v','dram_v','vbat_v','kdump_reserva_bytes','kdump_config_mib','kdump_sugerido_mib','secure_boot','mok'):
        if k in old['metricas'] and k in d['metricas']:
            print(f"  {k}: {old['metricas'][k]} → {d['metricas'][k]} (compare no mesmo computador)")
    for k in ('smart_desgaste_pct','smart_desligamentos_inseguros','smart_erros_midia'):
        if old[k] is not None and d[k] is not None: print(f'  {k}: {old[k]} → {d[k]} (último NVMe listado; compare apenas se for o mesmo disco)')
    sys.exit(0)
if action!='exportar': sys.exit('Ação inválida.')
write(p.with_suffix('.json'),json.dumps(d,ensure_ascii=False,indent=2)+'\n')
e=html.escape
items=lambda arr: ''.join('<li>'+e(x)+'</li>' for x in arr) or '<li>Nenhum registrado</li>'
levels=('CRÍTICO','ATENÇÃO','INFORMATIVO','NORMAL')
colors={'CRÍTICO':'#ff8484','ATENÇÃO':'#f2c77b','INFORMATIVO':'#8fc2ff','NORMAL':'#83dfb3'}
counts={k:sum(a['nivel']==k for a in d['achados']) for k in levels}
page="""<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Atualizar — Relatório</title><style> *{box-sizing:border-box}body{font:15px system-ui;background:#10151d;color:#e5e7eb;max-width:1080px;margin:32px auto;padding:0 20px}h1{font-size:2rem;color:#83dfb3;margin-bottom:4px}h2{font-size:1.2rem}section,details,.tile{background:#1c2532;border:1px solid #344254;border-radius:12px;padding:18px;margin:16px 0}li{margin:7px 0}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:13px monospace;line-height:1.5}summary{cursor:pointer}small{color:#aab8c9}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(155px,1fr));gap:12px}.tile{margin:0}.number{font-size:28px;font-weight:700}.tag{font-weight:700}.metrics{width:100%;border-collapse:collapse}.metrics td{padding:8px;border-bottom:1px solid #344254;overflow-wrap:anywhere}@media print{body{background:#fff;color:#111}section,details,.tile{background:#fff;color:#111;border:1px solid #999}.tag{color:#111!important}}</style></head><body><h1>Atualizar • Central de manutenção</h1><p>Relatório local | diagnóstico e histórico</p>"""
page+=f'<small>{e(d["inicio"])}</small><section><h2>Resultado</h2><p>{e(d["resultado"])}</p><p>{e(d["fim"] or "Sem encerramento registrado")}</p><p>Reinício: {e(d["reinicio"] or "Não registrado")}</p></section>'
page+='<div class="grid">'+''.join(f'<div class="tile"><div class="number" style="color:{colors[k]}">{counts[k]}</div><span>{k}</span></div>' for k in levels)+'</div>'
page+='<section><h2>Achados classificados</h2><ul>' + (''.join(f'<li><span class="tag" style="color:{colors.get(a["nivel"],"#aab8c9")}">{e(a["nivel"])}</span> — {e(a["mensagem"])}</li>' for a in d['achados']) or '<li>Nenhum registrado; não equivale a ausência de problemas.</li>')+'</ul></section>'
page+='<section><h2>Métricas coletadas</h2><table class="metrics">'+(''.join(f'<tr><td>{e(k)}</td><td>{e(str(v))}</td></tr>' for k,v in d['metricas'].items()) or '<tr><td>Nenhuma métrica estruturada neste relatório.</td></tr>')+'</table></section>'
page+=f'<section><h2>Etapas</h2><ul>{items(d["etapas"])}</ul></section><section><h2>Avisos ({len(d["avisos"])})</h2><ul>{items(d["avisos"])}</ul></section><details><summary>Relatório técnico completo</summary><pre>{e(text)}</pre></details><footer><small>As leituras são indicativas. Proteja este relatório: pode conter nomes de dispositivos, endereços de rede e registros locais.</small></footer></body></html>'
write(p.with_suffix('.html'),page)
print('HTML: '+str(p.with_suffix('.html'))+'\nJSON: '+str(p.with_suffix('.json')))
PYEXPORT
}
menu() {
    local escolha rc verde='' reset='' azul=''
    if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then verde=$'\e[1;32m'; azul=$'\e[1;36m'; reset=$'\e[0m'; fi
    while :; do
        printf '\n%s══════════════════════════════════════════════════%s\n' "$verde" "$reset"
        printf '%s ATUALIZADOR DEBIAN | CENTRAL DE MANUTENÇÃO%s\n' "$verde" "$reset"
        printf ' %s | %s / %s | kernel %s\n' "$(hostname)" "$DISTRO_LABEL" "$PKG_LABEL" "$(uname -r)"
        LC_ALL=C free -h | awk '/^Mem:/{print " RAM: " $3 " usada / " $2 " total"}'
        LC_ALL=C df -h / | awk 'NR==2{print " Disco: " $5 " ocupado | " $4 " livre"}'
        if command -v sensors >/dev/null; then LC_ALL=C sensors 2>/dev/null | awk '/^Tctl:/{print " CPU: " $2 " " $3;exit}'; fi
        if command -v nvidia-smi >/dev/null; then timeout 5s nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | awk '{print " NVIDIA: " $1 " °C"}'; fi
        printf '%s--------------------------------------------------%s\n' "$azul" "$reset"
        cat <<'MENU'
  01  Atualização completa (gerenciador nativo + Snap + Flatpak)
  02  Atualização e limpeza opcional (por distribuição)
  03  Diagnóstico completo do computador
  04  Verificar/simular pacotes (sem instalar)
  05  Diagnóstico de hardware
  06  Diagnóstico de rede e DNS
  07  Segurança do sistema (somente leitura)
  08  Histórico dos últimos 15 relatórios
  09  Exportar último relatório em HTML e JSON
  10  Recuperação / diagnóstico do gerenciador
  11  Kernel, firmware e Kdump
  12  Serviços, GNOME e falhas de aplicativos
  13  Monitor de hardware (10 amostras)
  14  Testes de estabilidade (com confirmação)
  15  Backup de configurações (com confirmação)
  16  Comparar último relatório com anterior
  00  Sair
MENU
        printf '\nSelecione uma opção: '; read -r escolha || return 0
        case $escolha in
            1|01) bash "$self" --atualizar;;
            2|02) bash "$self" --atualizar --limpeza;;
            3|03) bash "$self" --diagnostico;;
            4|04) bash "$self" --simular;;
            5|05) bash "$self" --hardware;;
            6|06) bash "$self" --rede;;
            7|07) bash "$self" --seguranca;;
            8|08) bash "$self" --historico;;
            9|09) bash "$self" --exportar;;
            10) bash "$self" --recuperacao;;
            11) bash "$self" --kernel;;
            12) bash "$self" --servicos;;
            13) bash "$self" --monitor --sem-sudo;;
            14) bash "$self" --testes;;
            15) bash "$self" --backup;;
            16) bash "$self" --comparar;;
            0|00|q|Q) return 0;;
            *) echo 'Opção inválida.'; continue;;
        esac
        rc=$?; printf '\nCódigo de saída: %s. Enter para voltar ao menu.' "$rc"; read -r escolha || return 0
    done
}
if (( EUID == 0 )); then echo 'Execute com seu usuário normal, sem sudo na frente.'; exit 2; fi
# Sem argumentos: menu quando há terminal; execução não-interativa não altera nada.
if (( $# == 0 )); then
    if [[ -t 0 && -t 1 ]]; then menu; exit $?; else set -- --diagnostico --sem-sudo; fi
fi
if [[ $# == 1 ]]; then
    case $1 in
        --menu) [[ -t 0 && -t 1 ]] || { echo 'Menu exige terminal.'; exit 2; }; menu; exit $?;;
        --historico|--exportar|--comparar) command -v python3 >/dev/null || { echo 'Python 3 indisponível.'; exit 2; }; exportar "${1#--}"; exit $?;;
    esac
fi
for arg in "$@"; do
    case "$arg" in
        --diagnostico|--simular|--hardware|--rede|--seguranca|--recuperacao|--atualizar|--kernel|--servicos|--monitor|--testes|--backup)
            if (( modo_explicito )) && [[ $modo != "${arg#--}" ]]; then echo 'Escolha apenas um modo.'; exit 2; fi
            modo=${arg#--}; modo_explicito=1 ;;
        --limpeza) limpeza=1 ;;
        --aceitar-flatpak) flatpak_sim=1 ;;
        --sem-sudo) sem_sudo=1 ;;
        --versao) echo '3.2-preview (debian)'; exit 0 ;;
        --distro) printf '%s | backend: %s\n' "$DISTRO_LABEL" "$PKG_LABEL"; exit 0 ;;
        --ajuda|-h) cat <<'HELP'
Uso: atualizador-debian [opções]
  Sem opções        Menu interativo (sem terminal: diagnóstico sem sudo).
  --atualizar      Atualiza gerenciador nativo + Snap/Flatpak instalados.
  --menu           Abre a central interativa.
  --hardware       Diagnóstico de hardware, drivers e SMART.
  --rede           Diagnóstico de rede local e resolução DNS pública.
  --seguranca      Consultas de segurança, sem modificar configurações.
  --historico      Lista os 15 relatórios TXT mais recentes.
  --exportar       Gera HTML e JSON do último relatório.
  --recuperacao    APT: reparo confirmado; Arch: diagnóstico não destrutivo.
  --diagnostico     Apenas consultas, sem instalar/remover pacotes.
  --simular         APT: prévia sem remoção; Arch: checkupdates ou índice local.
                    Não instala nem altera pacotes.
  --limpeza         Oferece limpeza de cache e dependências órfãs.
  --aceitar-flatpak Aceita atualizações e runtimes do Flatpak sem perguntar.
  --kernel         Metapacotes HWE, KHO, Kdump, MOK e logs do kernel.
  --servicos       Serviços, GNOME, AppArmor, Nextcloud e crashes (consulta).
  --monitor        10 amostras de CPU, RAM e GPU; não controla hardware.
  --testes         Testes curtos CPU/RAM, somente com confirmação.
  --backup         Cópia privada de LACT, CoolerControl e configurações locais.
  --comparar       Compara últimos relatórios finalizados do mesmo modo.
  --sem-sudo        Modos de consulta: omite consultas privilegiadas.
  --versao          Versão do script.
  --distro          Mostra distribuição e gerenciador selecionados.
  --ajuda, -h       Esta ajuda.
Exclusivo para ID=debian. Edição de testes, não homologada para produção.
Códigos: 0 concluído (pode haver avisos), 1 falha, 2 uso inválido,
         130/143 interrupção. Não reinicia nem repara automaticamente.
HELP
        exit 0 ;;
        *) printf 'Opção desconhecida: %s\n' "$arg"; exit 2 ;;
    esac
done
if (( EUID == 0 )); then echo 'Execute como usuário normal, sem sudo na frente.'; exit 2; fi
if [[ $modo == atualizar || $modo == recuperacao || $modo == testes || $modo == backup ]]; then
    if (( sem_sudo )) || [[ ! -t 0 ]]; then echo 'Este modo exige terminal interativo e autorização sudo.'; exit 2; fi
fi
if [[ $modo != atualizar ]] && (( limpeza || flatpak_sim )); then echo 'Limpeza e aceite Flatpak só no modo de atualização.'; exit 2; fi
# A validação de ID=debian ocorreu antes do processamento dos argumentos.
for cmd in flock mktemp tee timeout awk sort diff; do
    command -v "$cmd" >/dev/null || { echo "Comando essencial ausente: $cmd"; exit 2; }
done
# Implementação embutida e exclusiva desta distribuição.
# Não carrega módulos de outras distribuições nem bibliotecas externas.
existe() { command -v "$1" >/dev/null 2>&1; }
# Backend APT exclusivo da edição Debian.
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
        if [[ -n $nomes ]]; then achado NORMAL 'Pacotes de kernel Debian reconhecidos; presença do metapacote deve ser confirmada caso a caso.'; fi
    else achado ATENÇÃO 'Inventário do kernel APT indisponível.'; fi
    echo 'Metapacotes marcados como manuais:'; apt-mark showmanual | grep -E '^linux-' || :
    df -h /boot /boot/efi 2>/dev/null || :
    echo 'Debian — firmware e microcode (sem inferir que um pacote não instalado é obrigatório):'
    LC_ALL=C timeout 15s apt-cache policy firmware-linux firmware-amd-graphics amd64-microcode intel-microcode || :
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

pkg_requisitos || exit 2
baixados=$(xdg-user-dir DOWNLOAD 2>/dev/null) || baixados="$HOME/Downloads"
[[ $baixados == /* && $baixados != "$HOME" ]] || baixados="$HOME/Downloads"
pasta="$baixados/Relatorios-atualizador-debian"
[[ ! -L $pasta ]] || { echo 'Pasta de relatórios não pode ser link simbólico.'; exit 1; }
mkdir -p -m 0700 -- "$pasta" || exit 1
[[ -O $pasta ]] || { echo 'Pasta de relatórios deve pertencer ao usuário.'; exit 1; }
chmod 700 -- "$pasta" || exit 1
[[ ! -L $pasta/.em-execucao ]] || { echo 'Lock inválido.'; exit 1; }
exec 9>"$pasta/.em-execucao" || exit 1
flock -n 9 || { echo 'Outra atualização já está em andamento.'; exit 1; }
relatorio=$(mktemp --suffix=.txt "$pasta/atualizacao-$(date +%F_%H-%M-%S)-XXXXXX") || exit 1
work=$(mktemp -d) || exit 1
trap 'rm -rf -- "$work"' EXIT
exec 3>&1 4>&2
exec > >(trap '' INT; tee -a -- "$relatorio") 2>&1
tee_pid=$!
falhou=0; parcial=0; interrompido=0; sudo_ok=0; reinicio_antes=0
[[ -e /run/reboot-required ]] && reinicio_antes=1
trap 'interrompido=130' INT
trap 'interrompido=143' TERM
declare -a etapas=() avisos=()
declare -A avisos_vistos=() achados_vistos=()
declare -a achados=()
secao() { printf '\n===== %s =====\n' "$*"; }
aviso() { [[ ${avisos_vistos[$*]+x} ]] && return 0; avisos_vistos["$*"]=1; avisos+=("$*"); printf 'AVISO: %s\n' "$*"; }
pular() { etapas+=("$* — não executado"); printf '\nPULADO: %s\n' "$*"; }
existe() { command -v "$1" >/dev/null 2>&1; }
etapa() {
    local nome=$1 rc; shift
    if (( interrompido )); then pular "$nome (interrupção)"; return "$interrompido"; fi
    secao "$nome"
    if "$@"; then rc=0; else rc=$?; fi
    if (( interrompido )); then rc=$interrompido; fi
    if (( rc == 0 )); then etapas+=("$nome — concluído")
    else
        if [[ $nome == 'Flatpak — atualizar ('* && $rc == 1 ]]; then
            etapas+=("$nome — não concluído (código 1: cancelamento ou erro; confira a saída)")
        else etapas+=("$nome — falhou (código $rc)"); fi
        falhou=1
        if (( rc == 130 || rc == 143 )); then interrompido=$rc; fi
    fi
    return "$rc"
}
consulta() {
    local rc
    if (( interrompido )); then return 0; fi
    if timeout 30s "$@"; then :; else rc=$?; aviso "Consulta $1 retornou código $rc."; fi
}
confirmar() {
    local resposta
    if (( interrompido )); then return 1; fi
    printf '\n%s [s/N] ' "$1"
    read -r resposta || return 1
    [[ $resposta == [sSyY] || $resposta == sim || $resposta == SIM ]]
}
# Ponte única: funções do núcleo não conhecem apt-get, dpkg ou pacman.
integridade() { pkg_integridade; }
inventario() {
    local fase=$1
    pkg_inventario "$fase"
    if existe snap; then
        if ! LC_ALL=C timeout 25s snap list >"$work/snap.$fase"; then rm -f -- "$work/snap.$fase"; aviso "Inventário Snap $fase indisponível."; fi
    fi
    if existe flatpak; then
        if ! LC_ALL=C timeout 25s flatpak list --columns=ref,version,active,installation,origin | LC_ALL=C sort >"$work/flatpak.$fase"; then rm -f -- "$work/flatpak.$fase"; aviso "Inventário Flatpak $fase indisponível."; fi
    fi
}
estado() {
    secao "Estado do computador — $1"
    printf 'Sistema: %s\n' "$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-Linux}")"
    printf 'Computador: %s | Kernel: %s | Arquitetura: %s\n' "$(hostname)" "$(uname -r)" "$(uname -m)"
    uptime -p
    if existe lscpu; then LC_ALL=C lscpu | awk -F ': *' '/^Model name:|^CPU\(s\):|^Core\(s\) per socket:|^Thread\(s\) per core:/{print $1 ": " $2}'; fi
    for campo in board_vendor board_name bios_version bios_date; do
        if [[ -r /sys/class/dmi/id/$campo ]]; then printf '%s: %s\n' "$campo" "$(cat "/sys/class/dmi/id/$campo")"; fi
    done
    free -h
    df -hT / /boot /var "$HOME" | awk 'NR==1 || !visto[$NF]++'
}
comparar() {
    secao 'Alterações de pacotes e aplicativos'
    if [[ -f $work/pkg.antes && -f $work/pkg.depois ]]; then
        awk -F '\t' 'FILENAME==ARGV[1]{a[$1]=$2;next}
          {if(!($1 in a)){print "Instalado  " $1 "  " $2;n++}else if(a[$1]!=$2){print "Alterado   " $1 "  " a[$1] " → " $2;n++}delete a[$1]}
          END{for(k in a){print "Removido   " k "  " a[k];n++}if(!n)print "Nenhuma alteração de pacotes nativos."}' "$work/pkg.antes" "$work/pkg.depois" | LC_ALL=C sort
    else echo 'Comparação de pacotes nativos indisponível.'; fi
    local gestor rc
    for gestor in snap flatpak; do
        if [[ -f $work/$gestor.antes && -f $work/$gestor.depois ]]; then
            printf '\n%s ( - anterior / + posterior ):\n' "$gestor"
            if diff -u --label antes --label depois "$work/$gestor.antes" "$work/$gestor.depois"; then echo 'Nenhuma diferença.'
            else rc=$?; (( rc == 1 )) || aviso "Comparação $gestor falhou."; fi
        fi
    done
}
smart_diagnostico() {
    local disco tipo saida rc discos
    secao 'SMART — discos físicos'
    if ! existe smartctl || ! existe lsblk; then aviso 'SMART indisponível: smartmontools ou lsblk ausente.'; return; fi
    if (( !sudo_ok )); then aviso 'SMART omitido: sem autorização sudo.'; return; fi
    if ! discos=$(lsblk -dnpo NAME,TYPE); then aviso 'Não foi possível enumerar discos.'; return; fi
    while read -r disco tipo; do
        if (( interrompido )); then break; fi
        [[ $tipo == disk && $disco == /dev/* ]] || continue
        printf '\n--- %s ---\n' "$disco"
        if saida=$(sudo -n timeout 30s env LC_ALL=C smartctl -a "$disco" 2>&1); then rc=0; else rc=$?; fi
        printf '%s\n' "$saida" | sed -E '/Serial Number:|IEEE EUI-64:|LU WWN Device Id:|Logical Unit id:/Id'
        if (( rc == 124 || rc == 137 )); then aviso "SMART $disco: consulta expirada/encerrada."
        elif (( rc != 0 )); then
            if (( rc & 7 )); then aviso "SMART $disco: erro de consulta/acesso (código $rc)."; fi
            if (( rc & 24 )); then achado CRÍTICO "SMART $disco: possível falha/atributo crítico; revisar backup e diagnóstico."; fi
            if (( rc & 224 )); then aviso "SMART $disco: histórico de atributos, erros ou autotestes a revisar."; fi
        fi
        if printf '%s\n' "$saida" | grep -Eq 'Critical Warning:[[:space:]]+0x[0-9A-Fa-f]*[1-9A-Fa-f]'; then achado CRÍTICO "SMART $disco: alerta crítico NVMe."; fi
        if printf '%s\n' "$saida" | LC_ALL=C awk '$1==197 || $1==198 {if ($10+0>0) bad=1} END{exit !bad}'; then achado ATENÇÃO "SMART $disco: setores pendentes ou incorrigíveis registrados; verificar backup e evolução."; fi
        if printf '%s\n' "$saida" | LC_ALL=C awk '/^Percentage Used:/{if ($NF+0>=100) bad=1} END{exit !bad}'; then achado ATENÇÃO "SMART $disco: indicador de endurance NVMe >=100%; planejar avaliação/substituição."; fi
        if printf '%s\n' "$saida" | LC_ALL=C awk '/^Media and Data Integrity Errors:/{gsub(/[, .]/,"",$NF); if ($NF+0>0) n++} END{exit !n}'; then achado ATENÇÃO "SMART $disco: erros de integridade de mídia registrados; verificar evolução e backup."; fi
    done <<< "$discos"
}
pkg_pendentes_diagnostico() {
    pkg_pendentes
    if [[ $modo == simular ]]; then pkg_simular || aviso 'Simulação APT incompleta.'; fi
}
diagnostico() {
    local saida
    if (( interrompido )); then return; fi
    secao 'Unidades systemd com falhas'
    if existe systemctl; then
        local escopo; local -a args
        for escopo in sistema usuario; do
            args=(); [[ $escopo == usuario ]] && args+=(--user)
            if saida=$(LC_ALL=C timeout 20s systemctl "${args[@]}" --failed --no-legend --plain --no-pager 2>&1); then
                printf '%s: %s\n' "$escopo" "${saida:-Nenhuma unidade com falha.}"
                [[ -z $saida ]] || aviso "Unidades com falha no escopo $escopo; revisar acima."
            else aviso "systemd ($escopo) indisponível."; fi
        done
    fi
    secao 'Drivers gráficos, módulos e refrigeração'
    if existe lspci; then LC_ALL=C lspci -nnk | grep -Ei -A3 'VGA compatible controller|3D controller|Display controller' || :; fi
    if existe dkms; then consulta dkms status; fi
    if existe mokutil; then consulta mokutil --sb-state; fi
    if existe nvidia-smi; then consulta nvidia-smi --query-gpu=name,driver_version,temperature.gpu,power.draw,power.limit,utilization.gpu,memory.used,memory.total,fan.speed --format=csv; fi
    if existe systemctl && existe coolercontrold; then consulta systemctl is-active coolercontrold; fi
    if existe sensors; then
        secao 'Sensores — validação indicativa, não calibração'
        if saida=$(LC_ALL=C timeout 20s sensors 2>&1); then
            printf '%s\n' "$saida"
            if printf '%s\n' "$saida" | awk '/^pwm[0-9]+:/{if (($2+0)>100) n++} END{exit !n}'; then achado INFORMATIVO 'lm-sensors apresentou PWM acima de 100%; conferir valores diretos do sysfs abaixo.'; fi
        else printf '%s\n' "$saida"; aviso 'Sensores indisponíveis.'; fi
    else aviso 'lm-sensors ausente; temperaturas não coletadas.'; fi
    hardware_direto
    smart_diagnostico
    if existe journalctl; then
        secao 'Erros recentes do boot atual (até 40)'
        if (( sudo_ok )); then
            consulta sudo -n journalctl -b -p err -n 40 --no-pager --quiet
            secao 'Kernel — KHO e sensores NCT6687'
            if saida=$(sudo -n timeout 25s journalctl -k -b --no-pager --quiet 2>&1); then
                printf '%s\n' "$saida" | grep -Ei 'KHO:|nct6687|hwmon|nuvoton' | tail -n 40 || :
                [[ $saida != *'unlisted board'* ]] || aviso 'Driver de sensores utiliza perfil genérico; validar leituras.'
                [[ $saida != *'disabling kexec handover'* ]] || aviso 'Kexec handover desativado no boot; isoladamente não indica defeito da RAM.'
            else aviso 'Logs privilegiados do kernel indisponíveis.'; fi
        else consulta journalctl -b -p err -n 40 --no-pager --quiet; fi
        secao 'GNOME Keyring — apenas logs, sem acessar arquivos de senhas'
        if saida=$(timeout 20s journalctl --user -b -u gnome-keyring-daemon.service -n 60 --no-pager --quiet 2>&1); then
            printf '%s\n' "${saida:-Sem registros na consulta.}"
            [[ $saida != *'invalid or unrecognized format'* ]] || aviso 'GNOME Keyring: formato inválido de arquivo; não excluir sem análise e backup.'
        else aviso 'Logs GNOME Keyring indisponíveis.'; fi
        if existe coolercontrold; then secao 'CoolerControl — avisos recentes'; consulta journalctl -b -u coolercontrold -p warning -n 20 --no-pager --quiet; fi
    fi
    if existe snap; then secao 'Snap — inventário'; consulta snap list; fi
    if existe flatpak; then
        secao 'Flatpak — aplicativos e runtimes instalados'
        consulta flatpak list --app --columns=application,version,branch,installation
        consulta flatpak list --runtime --columns=application,branch,installation
        if saida=$(LC_ALL=C timeout 25s flatpak list --app --columns=application 2>&1); then
            [[ $saida != *'com.leinardi.gwe'* ]] || aviso 'GreenWithEnvy instalado; relatório anterior indicou fim de manutenção. Avalie migração.'
        fi
    fi
    if (( !interrompido )); then metapacotes; kdump_diag; modulos_seg; logs_contexto; servicos_diag; fi
}
rede() {
    secao 'Rede — interfaces, rota e DNS (sem alterar configurações)'
    if existe ip; then consulta ip -br link; consulta ip -br address; consulta ip route show default; consulta ip -6 route show default; fi
    if existe nmcli; then consulta nmcli -t -f DEVICE,TYPE,STATE device status; fi
    if existe resolvectl; then consulta resolvectl status; fi
    if existe getent; then
        local host
        local hosts=(kernel.org github.com)
        case $DISTRO_ID in
            ubuntu) hosts+=(archive.ubuntu.com security.ubuntu.com);;
            debian) hosts+=(deb.debian.org security.debian.org);;
            arch) hosts+=(archlinux.org);;
        esac
        for host in "${hosts[@]}"; do
            if (( interrompido )); then break; fi
            if timeout 10s getent ahosts "$host" >/dev/null; then printf 'DNS %s: OK\n' "$host"; else aviso "DNS $host: resolução indisponível ou expirada."; fi
        done
    fi
    if existe curl && [[ -t 0 ]] && confirmar 'Testar HTTPS dos repositórios públicos (sem instalar pacotes)?'; then
        local url
        local urls=(https://kernel.org/ https://github.com/)
        case $DISTRO_ID in
            ubuntu) urls+=(https://archive.ubuntu.com/ubuntu/ https://security.ubuntu.com/ubuntu/);;
            debian) urls+=(https://deb.debian.org/ https://security.debian.org/);;
            arch) urls+=(https://archlinux.org/);;
        esac
        for url in "${urls[@]}"; do
            if (( interrompido )); then break; fi
            if ! curl --head --silent --show-error --max-time 12 --output /dev/null --write-out '%{url_effective} HTTP %{http_code}\n' "$url"; then aviso "HTTPS indisponível: $url"; fi
        done
        echo 'HTTP 403/404 ainda pode demonstrar conectividade; não prova funcionamento do repositório.'
    fi
}
seguranca() {
    secao 'Segurança — verificações locais'
    if existe mokutil; then consulta mokutil --sb-state; fi
    if existe aa-status && (( sudo_ok )); then consulta sudo -n aa-status; fi
    if existe ufw && (( sudo_ok )); then consulta sudo -n ufw status; else echo 'UFW: consulta indisponível (não implica firewall desativado).'; fi
    if existe ss; then consulta ss -lntu; fi
    if existe lsblk; then consulta lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS; fi
    pkg_seguranca
    modulos_seg
    echo 'Não é auditoria de vulnerabilidades e não valida backups ou todas as regras de firewall.'
}
recuperar() { pkg_recuperar; }
# Diagnósticos 3.2: nenhuma escrita em sysfs, GRUB, drivers ou serviços.
metrica() { printf 'METRICA: %s=%s\n' "$1" "$2"; }
achado() {
    local nivel=$1; shift
    local mensagem="[$nivel] $*"
    [[ ${achados_vistos[$mensagem]+x} ]] && return 0
    achados_vistos["$mensagem"]=1
    achados+=("$mensagem")
    printf '%s\n' "$mensagem"
    case $nivel in CRÍTICO|ATENÇÃO) aviso "$mensagem";; esac
    return 0
}
ler() { local v; if [[ -r $1 ]] && IFS= read -r v < "$1"; then printf '%s' "$v"; else printf '?'; fi; }
bytes_mib() { LC_ALL=C awk -v n="$1" 'BEGIN {printf "%.1f",n/1048576}'; }
hardware_direto() {
    secao 'Hardware — leituras diretas de sysfs (somente leitura)'
    local board d nome i raw rpm p habil label v
    board=$(ler /sys/class/dmi/id/board_name)
    echo "Perfil DMI: $board"
    local msi=0 encontrado=0
    [[ $board == *MS-7E24* ]] && msi=1
    for d in /sys/class/hwmon/hwmon*; do
        [[ -d $d ]] || continue
        nome=$(ler "$d/name")
        if [[ $nome == k10temp ]]; then
            raw=$(ler "$d/temp1_input")
            if [[ $raw =~ ^-?[0-9]+$ ]]; then
                v=$(LC_ALL=C awk -v n="$raw" 'BEGIN{printf "%.1f",n/1000}')
                echo "CPU Tctl: $v °C"; metrica cpu_tctl_c "$v"
            fi
        fi
        [[ $nome == nct6687 ]] || continue
        encontrado=1
        printf '\n%s (%s)\n' "$nome" "$d"
        for p in "$d"/pwm[0-9]*; do
            [[ ${p##*/} =~ ^pwm([0-9]+)$ ]] || continue
            i=${BASH_REMATCH[1]}; raw=$(ler "$p"); rpm=$(ler "$d/fan${i}_input"); habil=$(ler "$d/pwm${i}_enable")
            label="Canal $i"
            if (( msi )); then
                case $i in 1) label=CPU_FAN1;; 2) label=PUMP_FAN1;; 3|4|5) label="SYS_FAN$((i-2))";; *) label="Canal $i (sem conector confirmado)";; esac
            fi
            if [[ $raw =~ ^[0-9]+$ ]] && (( raw <= 255 )); then
                v=$(LC_ALL=C awk -v n="$raw" 'BEGIN{printf "%.1f",n*100/255}')
                printf '%-36s | RPM %s | PWM %s/255 (%s%%) | modo %s\n' "$label" "$rpm" "$raw" "$v" "$habil"
                metrica "nct_pwm${i}_pct" "$v"
                [[ $rpm =~ ^[0-9]+$ ]] && metrica "nct_fan${i}_rpm" "$rpm"
            else achado ATENÇÃO "PWM $i fora da faixa 0–255 ou indisponível: $raw."; fi
            if (( msi && i == 2 )) && [[ $rpm == 0 ]]; then achado ATENÇÃO 'PUMP_FAN1 sem rotação detectada; confirme ligação e funcionamento da bomba.'; fi
        done
        for p in "$d"/in[0-9]*_input "$d"/temp[0-9]*_input; do
            [[ -e $p ]] || continue
            raw=$(ler "$p"); [[ $raw =~ ^-?[0-9]+$ ]] || continue
            i=${p##*/}; i=${i%_input}; label=$(ler "$d/${i}_label")
            v=$(LC_ALL=C awk -v n="$raw" 'BEGIN{printf "%.3f",n/1000}')
            if [[ $i == in* ]]; then habil=V; else habil=°C; fi
            printf '%-9s %-18s %s %s\n' "$i" "$label" "$v" "$habil"
            if (( msi )); then
                case $i in
                    in3) metrica soc_v "$v"; if LC_ALL=C awk -v n="$v" 'BEGIN{exit !(n>1.30)}'; then achado ATENÇÃO 'CPU SoC acima de 1,30 V nesta leitura; confirme na BIOS.'; fi;;
                    in7) metrica dram_v "$v";;
                    in5|in6|in8) achado INFORMATIVO 'MS-7E24: CPU 1P8, VDDP e Chipset têm divergências históricas com a BIOS; não interpretar como tensão real sem validar.';;
                    in13) metrica vbat_v "$v"; if LC_ALL=C awk -v n="$v" 'BEGIN{exit !(n<2.5)}'; then achado ATENÇÃO 'VBat abaixo de 2,5 V no NCT6687; confirmar fisicamente antes de substituir a bateria.'; fi;;
                    temp6|temp7) achado ATENÇÃO 'MS-7E24: canais PCIe x1 e M2_1 de temperatura não confirmados; comparar com sensores independentes e BIOS.';;
                esac
            fi
        done
        if (( msi )); then achado INFORMATIVO 'MS-7E24: cinco conectores físicos; 0 RPM em canais não conectados não comprova falha. O mapeamento permanece indicativo.'; fi
    done
    if (( encontrado )); then echo 'PWM calculado a partir do valor bruto: 100 × pwm / 255. Nenhum controle alterado.'; else echo 'NCT6687 não encontrado; perfil específico não aplicado.'; fi
    return 0
}
modulos_seg() {
    secao 'MOK, Secure Boot e assinatura dos módulos'
    local s m cert=/var/lib/shim-signed/mok/MOK.der
    if existe mokutil; then
        if s=$(LC_ALL=C timeout 15s mokutil --sb-state 2>&1); then
            echo "$s"
            if [[ $s == *'SecureBoot disabled'* ]]; then achado ATENÇÃO 'Secure Boot desativado: proteção de boot reduzida; não alterar automaticamente.'; metrica secure_boot disabled; elif [[ $s == *'SecureBoot enabled'* ]]; then metrica secure_boot enabled; fi
            [[ $s != *'Setup Mode'* ]] || achado INFORMATIVO 'UEFI em Setup Mode; ativação do Secure Boot exige avaliação das chaves de plataforma.'
        else echo "$s"; achado ATENÇÃO 'Estado Secure Boot indisponível.'; fi
        if [[ -f $cert ]] && (( sudo_ok )); then
            s=$(sudo -n timeout 15s env LC_ALL=C mokutil --test-key "$cert" 2>&1); echo "$s"
            if [[ $s == *'already enrolled'* ]]; then metrica mok enrolled; elif [[ $s == *'not enrolled'* ]]; then metrica mok not_enrolled; achado ATENÇÃO 'Certificado MOK local não cadastrado.'; else achado INFORMATIVO 'Não foi possível confirmar cadastro MOK.'; fi
        else echo 'Certificado local não consultado (arquivo ausente ou sem sudo).'; fi
    fi
    if [[ -r /sys/kernel/security/lockdown ]]; then printf 'Lockdown: %s\n' "$(ler /sys/kernel/security/lockdown)"; fi
    printf 'Taint global: %s\n' "$(ler /proc/sys/kernel/tainted)"
    for m in nvidia nct6687; do
        [[ -d /sys/module/$m ]] || continue
        echo "--- $m ---"
        if existe modinfo; then consulta modinfo -F signer "$m"; consulta modinfo -F sig_key "$m"; fi
        s=$(ler "/sys/module/$m/taint"); echo "Taint do módulo carregado: $s"
        if [[ $s == *E* ]]; then achado ATENÇÃO "$m: assinatura não validada pelo kernel (E), mesmo se houver assinatura no arquivo. Confira Secure Boot e MOK; não reinstalar automaticamente."; fi
        [[ $s != *P* && $s != *O* ]] || achado INFORMATIVO "$m: marca P/O de módulo proprietário/externo; não é necessariamente falha."
    done
    return 0
}
metapacotes() { pkg_kernel; }
kdump_diag() {
    secao 'Kernel — KHO e Kdump'
    local cmd n sugerido s loaded
    cmd=$(ler /proc/cmdline); echo "$cmd"
    [[ " $cmd " != *' kho=off '* ]] || achado INFORMATIVO 'KHO desativado explicitamente neste boot; Kdump pode continuar ativo.'
    n=$(ler /sys/kernel/kexec_crash_size); loaded=$(ler /sys/kernel/kexec_crash_loaded)
    echo "Kernel de captura carregado: $loaded"
    if [[ $n =~ ^[0-9]+$ ]]; then
        echo "Reserva real: $(bytes_mib "$n") MiB ($n bytes)"; metrica kdump_reserva_bytes "$n"
    fi
    if [[ $cmd =~ (^|[[:space:]])crashkernel=([0-9]+)M([[:space:]]|$) ]]; then metrica kdump_config_mib "${BASH_REMATCH[2]}"; fi
    if existe kdump-config; then
        if (( sudo_ok )); then
            if s=$(sudo -n timeout 25s env LC_ALL=C kdump-config show 2>&1); then
                printf '%s\n' "$s"
                sugerido=$(printf '%s\n' "$s" | sed -nE 's/^crashkernel suggested size:[[:space:]]*([0-9]+)M.*/\1/p' | head -n1)
                if [[ $sugerido =~ ^[0-9]+$ ]]; then
                    metrica kdump_sugerido_mib "$sugerido"
                    if [[ $n =~ ^[0-9]+$ ]] && (( n < sugerido*1048576 )); then achado ATENÇÃO 'Reserva real Kdump inferior à sugerida; não modificar GRUB automaticamente.'; fi
                fi
            else echo "$s"; achado ATENÇÃO 'Consulta kdump-config não concluída.'; fi
        else echo 'Estimador Kdump omitido sem sudo.'; fi
        if [[ $loaded == 1 ]]; then achado NORMAL 'Kernel de captura carregado; geração de dump real não testada.'; elif [[ $loaded == 0 ]]; then achado ATENÇÃO 'Kdump instalado, mas kernel de captura não carregado; verifique se foi desativado intencionalmente.'; fi
    else echo 'Kdump não instalado.'; fi
    return 0
}
logs_contexto() {
    secao 'Kernel — classificação contextual do boot atual'
    local logs s
    local -a j=(journalctl -k -b --no-pager --quiet -o short-iso)
    (( sudo_ok )) && j=(sudo -n "${j[@]}")
    if ! existe journalctl || ! logs=$(timeout 30s "${j[@]}" 2>&1); then achado ATENÇÃO 'Logs do kernel indisponíveis ou incompletos.'; return 0; fi
    if [[ -z $logs ]]; then achado INFORMATIVO 'Nenhum log do kernel acessível nesta consulta.'; return 0; fi
    printf '%s\n' "$logs" | grep -Ei 'KHO:|dcn10_program_hpd_filter|module verification failed|NVRM: Xid|Hardware Error|Machine Check|EDAC.*(error|UE)|I/O error|GPU reset|ring.*timeout|apparmor="DENIED"|unchecked data buffer|HCI Enhanced Setup' | tail -n 60 || :
    if [[ $logs == *'Failed to reserve scratch area'* || $logs == *'Failed to reserve lowmem scratch buffer'* ]]; then achado ATENÇÃO 'KHO: falha de reserva durante o boot; não comprova defeito de RAM.'; fi
    if [[ $logs == *dcn10_program_hpd_filter* ]]; then achado ATENÇÃO 'AMDGPU HPD: aviso na inicialização do driver; acompanhar correções e sintomas gráficos.'; fi
    if printf '%s\n' "$logs" | grep -Eiq 'NVRM: Xid|GPU reset|ring.*timeout'; then achado ATENÇÃO 'Kernel registrou eventos de GPU (Xid/reset/timeout); avaliar contexto e recorrência.'; fi
    if printf '%s\n' "$logs" | grep -Eiq 'Hardware Error|Machine Check Exception|EDAC.*(uncorrected| UE)|I/O error|Buffer I/O error|Kernel panic'; then achado CRÍTICO 'Kernel registrou possível falha grave de hardware ou E/S; revisar logs e backups.'; fi
    if [[ $logs == *'module verification failed'* ]]; then achado ATENÇÃO 'Kernel registrou falha de validação de assinatura de módulo.'; fi
    if [[ $logs == *'unchecked data buffer'* ]]; then achado INFORMATIVO 'NVMe: aviso unchecked data buffer; não equivale a erro SMART de mídia.'; fi
    if [[ $logs == *'HCI Enhanced Setup Synchronous Connection'* ]]; then achado INFORMATIVO 'Bluetooth: comando HCI anunciado mas não suportado; acompanhar sintomas.'; fi
    if [[ $logs == *'apparmor="DENIED"'* ]]; then
        achado ATENÇÃO 'AppArmor registrou bloqueios; analisar aplicação e impacto sem desativar a proteção.'
        if [[ $logs == *snap.nextcloud.nextcloud-fixer* ]]; then achado ATENÇÃO 'Nextcloud Snap fixer: bloqueios no AppArmor; apenas registrar, sem parar ou remover o Nextcloud.'; fi
    fi
    return 0
}
servicos_diag() {
    secao 'Serviços e falhas de aplicações'
    local s u init active
    for u in lactd coolercontrold kdump-tools nvidia-powerd nvidia-persistenced apparmor; do
        init=$(systemctl is-enabled "$u" 2>/dev/null || :); active=$(systemctl is-active "$u" 2>/dev/null || :)
        printf '%s: %s / %s\n' "$u" "${init:-indisponível}" "${active:-indisponível}"
        if [[ $active == failed ]]; then achado ATENÇÃO "Serviço $u em falha."; fi
    done
    if existe journalctl; then
        local -a j=(journalctl -b --no-pager --quiet -o short-iso)
        (( sudo_ok )) && j=(sudo -n "${j[@]}")
        if s=$(timeout 25s "${j[@]}" --grep='gkr-pam:' 2>&1); then
            printf '%s\n' "${s:-PAM: sem registros acessíveis.}"
            if [[ $s == *'unlocked login keyring'* ]]; then achado NORMAL 'PAM registrou desbloqueio do chaveiro Login neste boot.'; elif [[ $s == *'unable to locate daemon control file'* ]]; then achado ATENÇÃO 'PAM não encontrou socket do Keyring e não há confirmação de desbloqueio nos logs consultados.'; fi
        fi
        if s=$(timeout 20s journalctl --user -b -u gnome-keyring-daemon.service --no-pager --quiet 2>&1); then
            [[ $s != *'invalid or unrecognized format'* ]] || achado ATENÇÃO 'GNOME Keyring: formato inválido; preservar credenciais e investigar.'
            [[ $s != *'already registered'* ]] || achado INFORMATIVO 'GNOME Keyring: avisos de registro duplicado; não comprovam corrupção.'
        fi
    fi
    if existe busctl; then
        if s=$(timeout 8s busctl --user --auto-start=no get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Locked 2>/dev/null); then
            echo "Keyring Login Locked: $s"; [[ $s != 'b false' ]] || achado NORMAL 'Chaveiro Login desbloqueado nesta sessão.'
        else echo 'Estado do chaveiro Login indisponível (sem iniciar serviço).'; fi
    fi
    if existe snap && timeout 12s snap list nextcloud >/dev/null 2>&1; then
        echo 'Nextcloud Snap local detectado. Nenhuma modificação será feita.'; consulta snap services nextcloud
        if (( sudo_ok )); then
            if s=$(sudo -n timeout 15s snap logs -n=20 nextcloud.nextcloud-fixer 2>&1); then
                printf '%s\n' "$s" | tail -n 8
                if [[ $s == *'Nextcloud is not installed'* ]]; then achado ATENÇÃO 'Nextcloud local não configurado: fixer registra tentativas recorrentes. Instalação mantida.'; fi
            fi
        fi
    fi
    secao 'LACT e CoolerControl — indicação de controle de GPU'
    if (( sudo_ok )) && [[ -d /etc/lact ]]; then
        # Só chaves de configuração selecionadas; não ler tokens nem senhas.
        s=$(sudo -n timeout 8s grep -E '^[[:space:]]*(fan_control_enabled|power_mizer_mode|target_temperature|voltage_boost|power_cap):' /etc/lact/config.yaml 2>/dev/null || :)
        printf '%s\n' "${s:-Configuração LACT não acessível ou sem chaves selecionadas.}"
        if [[ $s == *'fan_control_enabled: true'* ]]; then achado INFORMATIVO 'LACT tem controle de ventoinha habilitado em configuração; confirme que CoolerControl não aplica outro perfil à mesma GPU.'; fi
    fi
    if existe powerprofilesctl; then consulta powerprofilesctl get; fi
    secao 'Relatórios de falhas — somente nomes, datas e tamanhos'
    if [[ -d /var/crash ]]; then
        s=$(find /var/crash -maxdepth 1 -type f -name '*.crash' -printf '%TY-%Tm-%Td %TH:%TM:%TS | %s bytes | %f\n' 2>/dev/null | sort -r)
        printf '%s\n' "${s:-Nenhum relatório visível.}"
        [[ -z $s ]] || achado INFORMATIVO 'Existem relatórios de falhas de aplicativos; datas antigas não indicam falha no boot atual.'
    fi
    if existe coredumpctl; then consulta coredumpctl --no-pager -n 10 list; else echo 'coredumpctl não instalado; preservado o mecanismo Apport existente.'; fi
    return 0
}
historico_boot() {
    secao 'Histórico de boots — avisos selecionados (até 4 boots anteriores)'
    local i s
    local -a j=(journalctl -k --no-pager --quiet -o short-iso)
    (( sudo_ok )) && j=(sudo -n "${j[@]}")
    if ! existe journalctl; then return 0; fi
    consulta journalctl --list-boots -n 8 --no-pager
    for i in -1 -2 -3 -4; do
        (( interrompido )) && break
        if s=$(timeout 12s "${j[@]}" -b "$i" --grep='dcn10_program_hpd_filter|Failed to reserve.*scratch|failed boot timer expired|NVRM: Xid|Hardware Error|Machine Check Exception|I/O error' -n 12 2>/dev/null); then
            printf 'Boot %s — %s\n' "$i" "${s:-sem correspondências acessíveis}"
        else printf 'Boot %s — sem correspondências ou sem histórico acessível.\n' "$i"; fi
    done
    echo 'Ocorrências anteriores não demonstram falha atual nem identificam, sozinhas, a causa de um reboot.'
    return 0
}
monitorar() {
    secao 'Monitor de hardware — 10 amostras, intervalo de 2 segundos'
    local i
    for ((i=1;i<=10;i++)); do
        (( interrompido )) && break
        printf '\nAmostra %s/10 — %s\n' "$i" "$(date +%T)"
        free -h | awk 'NR<=2'; cat /proc/loadavg
        if existe sensors; then LC_ALL=C timeout 5s sensors 2>/dev/null | grep -Ei '^Tctl:|^Composite:|^Pump Fan:|^System Fan #2:|^CPU Soc:' || :; fi
        if existe nvidia-smi; then timeout 5s nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu,clocks.gr --format=csv || :; fi
        (( i == 10 )) || sleep 2
    done
    echo 'Fim do monitor. Não houve alterações de frequência, potência ou ventoinhas.'
}
testes_estabilidade() {
    secao 'Estabilidade — testes opcionais, carga real'
    local workers avail mb
    echo 'Salve os trabalhos antes. Testes podem aquecer o sistema ou causar travamento se instável. Ctrl+C interrompe. Não substituem teste prolongado de RAM/GPU.'
    if existe stress-ng; then
        workers=$(getconf _NPROCESSORS_ONLN); [[ $workers =~ ^[1-9][0-9]*$ ]] || workers=1; (( workers>4 )) && workers=4
        if confirmar "Executar stress-ng CPU por 60 segundos, $workers workers, com verificação?"; then
            etapa 'Teste CPU (60 s)' timeout -k 10s 90s stress-ng --cpu "$workers" --verify --timeout 60s --metrics-brief || achado ATENÇÃO 'Teste CPU não concluído com sucesso.'
        else pular 'Teste CPU não autorizado'; fi
    else pular 'stress-ng não instalado'; fi
    (( interrompido )) && return 0
    if existe memtester && (( sudo_ok )); then
        avail=$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo); [[ $avail =~ ^[0-9]+$ ]] || avail=0
        mb=$((avail/4)); (( mb>1024 )) && mb=1024
        if (( mb >= 128 )) && confirmar "Executar memtester de ${mb} MiB, 1 ciclo (máximo 10 min)?"; then
            etapa 'Teste RAM (amostra limitada)' sudo -n timeout -k 10s 600s memtester "${mb}M" 1 || achado ATENÇÃO 'Teste RAM falhou ou foi interrompido; confira a saída antes de concluir defeito.'
        else pular 'Teste RAM não autorizado ou RAM disponível insuficiente'; fi
    else pular 'memtester ou sudo indisponível'; fi
    return 0
}
backups() {
    secao 'Backup de configurações — não é imagem completa do sistema'
    echo 'Cópia root-only de configurações conhecidas de cada sistema, se existentes; sem seguir links. Pode conter segredos. Não é backup completo.'
    if (( !sudo_ok )); then achado ATENÇÃO 'Backup exige autorização sudo.'; falhou=1; return; fi
    if ! confirmar 'Criar backup privado e verificar cópias?'; then pular 'Backup não autorizado'; return; fi
    sudo -n bash -c '
        set -eu; umask 077
        base=/var/backups/atualizador-debian
        [[ ! -L $base ]] || exit 1
        install -d -m 700 -o root -g root "$base"
        [[ $(stat -c %u "$base") == 0 ]] || exit 1
        chmod 700 "$base"
        dest=$(mktemp -d "$base/backup-$(date +%Y%m%d-%H%M%S)-XXXXXX")
        printf "Backup em: %s\n" "$dest"
        for p in /etc/lact /etc/coolercontrol /etc/default/grub /etc/default/grub.d /etc/default/kdump-tools /etc/apt/sources.list /etc/apt/sources.list.d; do
            if [[ -e $p || -L $p ]]; then cp -a --parents -- "$p" "$dest/"; diff -qr --no-dereference "$p" "$dest$p"; echo "Conferido: $p"; else echo "Ausente: $p"; fi
        done
        touch "$dest/.concluido"
        echo "Backup concluído; nenhuma restauração automática."
    '
}

echo 'AVISO: edição 3.2-preview experimental; testes reais de atualização/limpeza ainda limitados. Revise o código e mantenha backups.'
inicio=$(date +%s)
printf 'Atualizador Debian 3.2-preview | Distribuição: %s | Backend: %s | Modo: %s | Início: %s\nRelatório: %s\n' "$DISTRO_LABEL" "$PKG_LABEL" "$modo" "$(date '+%d/%m/%Y %H:%M:%S %Z')" "$relatorio"
metrica distro_id "$DISTRO_ID"
if (( !sem_sudo )) && [[ $modo != rede && $modo != monitor ]]; then
    if existe sudo && { if [[ -t 0 ]]; then sudo -v; else sudo -n -v; fi; }; then sudo_ok=1; etapas+=('Autorização sudo — concluída')
    elif [[ $modo == atualizar || $modo == recuperacao || $modo == testes || $modo == backup ]]; then falhou=1; pular 'Autorização sudo (APT/Snap indisponíveis)'
    else aviso 'Sem sudo: parte do diagnóstico será omitida.'; fi
fi
case $modo in
    kernel) if (( !interrompido )); then estado Atual; etapa 'Metapacotes do kernel' metapacotes || :; etapa 'KHO e Kdump' kdump_diag || :; etapa 'Assinaturas dos módulos' modulos_seg || :; etapa 'Logs do kernel' logs_contexto || :; historico_boot; fi;;
    servicos) if (( !interrompido )); then etapa 'Serviços e aplicativos' servicos_diag || :; etapa 'Logs do kernel e AppArmor' logs_contexto || :; fi;;
    monitor) if (( !interrompido )); then etapa 'Monitor de hardware' monitorar || :; fi;;
    testes) if (( !interrompido )); then if (( sudo_ok )); then etapa 'Testes opcionais de estabilidade' testes_estabilidade || :; else pular 'Sem sudo'; fi; fi;;
    backup) if (( !interrompido )); then etapa 'Backup de configurações' backups || :; fi;;
    rede) if (( !interrompido )); then etapa "Diagnóstico de rede" rede || :; fi;;
    seguranca) if (( !interrompido )); then etapa "Diagnóstico de segurança" seguranca || :; fi;;
    hardware) if (( !interrompido )); then estado Atual; diagnostico; fi;;
    recuperacao) if (( !interrompido )); then inventario antes; recuperar; if (( !interrompido )); then inventario depois; comparar; fi; fi;;
    *)
if (( !interrompido )); then estado Antes; inventario antes; fi
pre_ok=0; pkg_ok=0
if (( !interrompido )) && etapa "Integridade $PKG_LABEL inicial" integridade; then pre_ok=1; fi
if [[ $modo == atualizar ]] && (( !interrompido )); then
    if (( sudo_ok && pre_ok )); then
        if pkg_atualizar; then pkg_ok=1; fi
    else pular "$PKG_LABEL — sem sudo ou integridade inicial falhou"; falhou=1; fi
    if (( limpeza && pkg_ok && !interrompido )); then pkg_limpar; fi

    if (( !pkg_ok )); then
        pular 'Snap e Flatpak — atualização nativa não concluída; sem alterações adicionais'
    elif (( !interrompido )); then
        if existe snap; then
            if (( sudo_ok )) && confirmar 'Autorizar atualização dos Snaps instalados?'; then
                etapa 'Snap — atualizar aplicativos' sudo snap refresh || :
            else pular 'Snap — atualização não autorizada'; fi
        else pular 'Snap — não instalado'; fi
    fi
    if (( pkg_ok && !interrompido )); then
        if existe flatpak; then
            fp_args=(); (( flatpak_sim )) && fp_args+=(--assumeyes)
            if (( !flatpak_sim )); then echo 'Flatpak: revise os aplicativos e runtimes solicitados antes de aceitar.'; fi
            for escopo in system user; do
                if (( interrompido )); then break; fi
                if (( !flatpak_sim )) && ! confirmar "Executar atualização Flatpak ($escopo)?"; then
                    pular "Flatpak — atualização ($escopo) não autorizada"; parcial=1; continue
                fi
                if etapa "Flatpak — atualizar ($escopo)" flatpak update "--$escopo" "${fp_args[@]}"; then
                    if (( limpeza )) && confirmar "Verificar e remover runtimes não usados ($escopo)? Confira a lista antes de aceitar."; then etapa "Flatpak — limpeza ($escopo)" flatpak uninstall "--$escopo" --unused || :; fi
                fi
            done
        else pular 'Flatpak — não instalado'; fi
    fi
fi
if (( !interrompido )); then
    estado Depois; inventario depois; comparar
    if [[ $modo != atualizar ]] || (( !pkg_ok )); then etapa "Integridade $PKG_LABEL final" integridade || :; fi
    if (( !interrompido )); then pkg_pendentes_diagnostico; fi
    if (( !interrompido )); then diagnostico; fi
fi
    ;;
esac
secao 'RESUMO FINAL'
printf 'Fim: %s | Duração: %s segundos\n' "$(date '+%d/%m/%Y %H:%M:%S %Z')" "$(( $(date +%s)-inicio ))"
if (( interrompido )); then echo 'Resultado: interrompido; verifique estado antes de repetir.'
elif (( falhou || parcial )); then echo 'Resultado: execução parcial (falha ou etapa de atualização não autorizada).'
elif [[ $modo == atualizar ]]; then echo 'Resultado: atualização concluída; revise avisos e pendências.'
elif [[ $modo == recuperacao ]]; then echo 'Resultado: recuperação encerrada; confira as etapas.'; elif [[ $modo == backup || $modo == testes ]]; then echo 'Resultado: rotina opcional encerrada; confira etapas executadas e puladas.'; else echo 'Resultado: diagnóstico/simulação concluído sem instalar pacotes.'; fi
if ((${#etapas[@]})); then printf '  • %s\n' "${etapas[@]}"; fi
printf '\nAvisos registrados: %s\n' "${#avisos[@]}"
if ((${#avisos[@]})); then printf '  • %s\n' "${avisos[@]}"; fi
printf '\nAchados classificados: %s\n' "${#achados[@]}"
if ((${#achados[@]})); then printf '  • %s\n' "${achados[@]}"; fi
if [[ -e /run/reboot-required ]]; then
    if (( reinicio_antes )); then echo 'Reinício: já pendente no início.'; else echo 'Reinício: indicado pelo sistema.'; fi
    if [[ -r /run/reboot-required.pkgs ]]; then sort -u /run/reboot-required.pkgs; fi
else echo 'Reinício: sem marcador de reboot-required (não garante que reinicialização seja desnecessária).'; fi
echo 'Nenhum reboot automático será realizado.'
printf '\nRelatório salvo em %s\n' "$relatorio"
exec 1>&3 2>&4
exec 3>&- 4>&-
if ! wait "$tee_pid"; then printf 'Falha ao finalizar o relatório: %s\n' "$relatorio" >&2; falhou=1; fi
if (( !interrompido )) && existe python3; then
    if historico=$(exportar comparar "$relatorio"); then
        if [[ -n $historico ]]; then printf '\n%s\n' "$historico" | tee -a -- "$relatorio"; fi
    else echo 'Comparação histórica indisponível.'; fi
    exportar exportar "$relatorio" || { echo 'Falha ao gerar HTML/JSON; TXT preservado.'; falhou=1; }
fi
if (( interrompido )); then exit "$interrompido"; fi
exit "$(( falhou || parcial ))"
