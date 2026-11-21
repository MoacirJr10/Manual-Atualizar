# Atualizador Linux — Ubuntu, Debian e Arch

![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue) ![Bash](https://img.shields.io/badge/Bash-script-4EAA25) ![Estado](https://img.shields.io/badge/estado-testes%20limitados-orange)

Central open source de atualização, diagnóstico, limpeza opcional, monitoramento de hardware e relatórios locais.

> **AVISO IMPORTANTE — SOFTWARE NÃO AMPLAMENTE TESTADO.** As duas edições estão disponíveis para avaliação e contribuições, mas não foram validadas em grande variedade de distribuições, máquinas e cenários de atualização. Faça backup dos dados, leia o código e teste preferencialmente em máquina virtual. **Não recomendamos uso em servidores de produção.**

## Escolha a edição adequada

| Edição | Script | Suporte declarado | Maturidade |
|---|---|---|---|
| **Atualizador Ubuntu** | [`atualizador-ubuntu.sh`](atualizador-ubuntu.sh) | Ubuntu (`ID=ubuntu`) | Diagnósticos exercitados em Ubuntu 26.04.1; atualização/limpeza/recuperação sem validação ampla |
| **Atualizador Ubuntu, Debian e Arch** | [`atualizador-ubuntu-debian-arch.sh`](atualizador-ubuntu-debian-arch.sh) | Ubuntu, Debian ou Arch (`ID` exato) | **Prévia experimental**; Debian: simulação isolada; Arch e Ubuntu: testes simulados da nova edição |

Os identificadores técnicos continuam sendo **3.1 (Ubuntu)** e **3.2-preview (multiplataforma)**, mas os nomes dos arquivos descrevem onde cada edição funciona.

### 1. Atualizador Ubuntu

Script único para Ubuntu, baseado em APT/dpkg. Também consulta Snap e Flatpak quando instalados. Exemplos **sem alterar pacotes**:

```bash
bash -n atualizador-ubuntu.sh
bash atualizador-ubuntu.sh --versao
bash atualizador-ubuntu.sh --simular --sem-sudo
bash atualizador-ubuntu.sh --hardware --sem-sudo
```

[Manual ilustrado da edição Ubuntu (PDF)](Manual-Atualizador-Ubuntu.pdf). O PDF foi escrito para a versão técnica 3.1; os comandos devem usar o novo nome do arquivo, ou o comando `atualizar` após instalação local.

### 2. Atualizador Ubuntu, Debian e Arch — prévia experimental

Núcleo compartilhado e backends isolados por distribuição:

- **Ubuntu:** `lib/atualizar/ubuntu.sh` → `apt.sh` (APT/dpkg, com tratamento de faseamento).
- **Debian:** `lib/atualizar/debian.sh` → `apt.sh` (APT/dpkg, sem pressupostos exclusivos do Ubuntu).
- **Arch Linux:** `lib/atualizar/arch.sh` (`pacman -Syu` somente em atualização completa). **Não executa `pacman -Sy` isolado** nem atualiza AUR automaticamente.

A prévia **não oferece garantia de simular integralmente as transações do pacman**; `--simular` no Arch lista atualizações possíveis, não valida previamente todos os conflitos. Derivados (Mint, Manjaro, EndeavourOS, Pop!_OS etc.) não são identificados automaticamente como suportados.

Para consultar **sem instalar ou atualizar**:

```bash
bash -n atualizador-ubuntu-debian-arch.sh
bash instalar.sh --verificar
python3 tests/test_backends.py
bash atualizador-ubuntu-debian-arch.sh --versao
bash atualizador-ubuntu-debian-arch.sh --distro
bash atualizador-ubuntu-debian-arch.sh --simular --sem-sudo
bash atualizador-ubuntu-debian-arch.sh --hardware --sem-sudo
```

**Importante:** mantenha `lib/atualizar/` no mesmo diretório do script. O instalador opcional `instalar.sh` foi feito **somente para a edição multiplataforma**; antes de executá-lo, confira os arquivos e saiba que a instalação substitui `~/.local/bin/atualizar` **após sua confirmação e backup**. Para avaliar a prévia, prefira executá-la diretamente, sem instalar.

## Recursos compartilhados

- Atualização nativa (APT no Ubuntu/Debian e pacman no Arch), com confirmação e limpeza opcional.
- Snap e Flatpak somente se instalados; atualização e operações sensíveis exigem autorização.
- Diagnósticos de serviços, drivers, kernel, Kdump, assinatura de módulos, AppArmor, SMART e sensores.
- Monitoramento de CPU, GPU, SSD, PWM e refrigeração quando os sensores estão disponíveis.
- Simulação/consulta de pacotes, comparação e histórico de relatórios, exportações em TXT, HTML e JSON.
- Rotinas opcionais de backup de configurações, testes de estabilidade e diagnóstico/recuperação de pacotes.

**Não use o script com `sudo` à frente.** Ele solicita autorização somente quando o modo precisa. Revise as propostas de remoção. Em Arch, leia os [avisos oficiais](https://archlinux.org/news/) antes de `pacman -Syu`.

## Limitações e testes realizados

- **Ubuntu:** teste de diagnósticos, simulação e monitoramento em uma máquina Ubuntu 26.04.1 LTS. Atualizações reais, backups e recuperações da edição atual não receberam testes abrangentes.
- **Debian:** execução de simulação não destrutiva no Debian 13 em ambiente isolado. Atualizações reais não testadas.
- **Arch:** verificação de seleção do backend, simulação e chamada a `pacman -Syu` com comandos simulados. **Sem validação em instalação Arch real.**
- **Multiplataforma:** não foi testada com atualizações reais, limpezas ou recuperação nas três distribuições. Não testada em ambientes de produção.

**Status:** prévia para colaboração e revisão, não uma garantia de segurança ou compatibilidade. Sem telemetria; relatórios ficam em `~/Downloads/Relatorios-atualizar/` e podem conter dados privados. Não publique relatórios brutos nem backups.

## Verificação de integridade

```bash
sha256sum -c SHA256SUMS
```

Arquivos excluídos do controle de versão por `.gitignore` não substituem a revisão manual do que será enviado ao Git.

## Contribuições e revisão de segurança

O projeto é aberto sob [licença MIT](LICENSE). **Sugestões, relatos de bugs, traduções e Pull Requests são sempre bem-vindos!** Leia [CONTRIBUTING.md](CONTRIBUTING.md). Mudanças devem ser revisadas antes de entrar na branch protegida `main`, especialmente comandos privilegiados, downloads, alterações de permissões ou rotinas de limpeza.

Autor: [MoacirJr10](https://github.com/MoacirJr10).
