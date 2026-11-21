# Atualizadores para Ubuntu, Debian e Arch Linux

> **Edições experimentais 3.2-preview — NÃO amplamente testadas.**
> **A versão estável anterior (`atualizar-v3.1.sh`) continua intacta.**
> Nem a execução de comandos de consulta nem o sucesso em testes simulados garantem segurança em atualizações reais. Antes de usar os modos de atualização, limpeza ou reparação, revise o código e faça backup.

As edições são **três scripts independentes**. Não existe um instalador universal nem um seletor de distribuições. Cada script usa somente o gerenciador nativo esperado e recusa execução em outro `ID` de `/etc/os-release`.

| Edição | Código-fonte | Gerenciador nativo | Verificações específicas | Estado |
|---|---|---|---|---|
| **Atualizador Ubuntu** | [`edicoes/ubuntu/atualizador-ubuntu.sh`](edicoes/ubuntu/atualizador-ubuntu.sh) | APT/dpkg | Atualizações graduais, firmware Ubuntu, metapacotes de kernel | Prévia experimental; derivada dos diagnósticos do Atualizar 3.1 |
| **Atualizador Debian** | [`edicoes/debian/atualizador-debian.sh`](edicoes/debian/atualizador-debian.sh) | APT/dpkg | Kernel, firmware e dependências Debian | Prévia experimental; testes não destrutivos limitados |
| **Atualizador Arch** | [`edicoes/arch/atualizador-arch.sh`](edicoes/arch/atualizador-arch.sh) | Pacman | `checkupdates`, órfãos, `paccache`, inventário de pacotes externos | Prévia experimental; testes com pacman simulado |

Não há compatibilidade prometida para distribuições derivadas, como Mint, Pop!_OS, EndeavourOS ou Manjaro. O `ID` precisa ser `ubuntu`, `debian` ou `arch`, respectivamente. O projeto **não automatiza** mudanças de versão principal (release upgrades) nem gestão do AUR (`yay`/`paru`).

## Testar sem instalar

```bash
# Escolha APENAS a edição do seu sistema.
bash edicoes/ubuntu/atualizador-ubuntu.sh --distro
bash edicoes/debian/atualizador-debian.sh --distro
bash edicoes/arch/atualizador-arch.sh --distro
```

Os comandos acima devem ser executados **individualmente no sistema correspondente**. Uma edição executada em outra distribuição deve retornar erro antes de criar relatórios ou manipular pacotes.

```bash
# Exemplo somente no Ubuntu:
bash -n edicoes/ubuntu/atualizador-ubuntu.sh
bash edicoes/ubuntu/atualizador-ubuntu.sh --ajuda
bash edicoes/ubuntu/atualizador-ubuntu.sh --simular --sem-sudo
```

Para Debian ou Arch, substitua o caminho pelo da respectiva edição. Nenhum dos scripts substitui automaticamente o comando `atualizar` já instalado. Os modos de atualização, recuperação, backup e estresse requerem terminal e confirmação.

### Gerenciadores e limpeza

**Ubuntu:** atualização APT com simulação antes de instalar e sem remoção de pacotes por `dist-upgrade`; limpeza APT apenas mediante confirmação. Política de faseamento consultada apenas nesta edição.

**Debian:** fluxo APT análogo, sem políticas e pacotes específicos do Ubuntu; não executa migração entre releases.

**Arch:** atualizações oficiais somente com `pacman -Syu` integral, após confirmação. **Nunca `pacman -Sy` isolado**. O modo de consulta utiliza `checkupdates`, quando disponível, ou índices locais via `pacman -Qu` e não representa simulação completa de transação. Limpeza de órfãos e cache opcional, nunca automática; pacotes AUR são inventariados, mas não atualizados.

Referências: [ArchWiki — manutenção do sistema](https://wiki.archlinux.org/title/System_maintenance_(Portugu%C3%AAs)) · [Debian — gerenciamento de pacotes](https://www.debian.org/doc/manuals/debian-reference/ch02.html)

### Diagnósticos e relatórios

As três edições oferecem diagnósticos de sistema, CPU, GPU, temperatura, armazenamento SMART, rede, serviços, logs, kernel, segurança, além de histórico e exportação local TXT/HTML/JSON. A disponibilidade dos sensores depende do hardware, das permissões e dos utilitários instalados. Alguns diagnósticos têm origem no ambiente Ubuntu de desenvolvimento e podem retornar informação insuficiente ou avisos de ferramenta ausente em outras distribuições.

Cada edição utiliza uma pasta exclusiva em Downloads:

- `Relatorios-atualizador-ubuntu/`
- `Relatorios-atualizador-debian/`
- `Relatorios-atualizador-arch/`

Relatórios podem revelar IPs, nomes de máquinas e caminhos; revise-os antes de compartilhar.

## O que foi e o que NÃO foi testado

**Validado:** sintaxe Bash das três edições, detecção da distribuição por `ID`, isolamento estático dos gerenciadores, verificações de versão/ajuda e testes simulados de consulta. O backend Debian já foi consultado em ambiente de teste Debian; Arch foi exercitado com mocks (não em máquina Arch real). A versão Ubuntu anterior validou diagnósticos em um Ubuntu real, mas a nova edição separada necessita testes próprios.

**Ainda não validado amplamente:** atualização e limpeza reais, recuperação APT, efeitos da atualização de kernel, dispositivos variados, ambientes gráficos diferentes, todas as versões suportadas de Debian/Ubuntu e Arch em hardware real, autorizações `sudo`, backups e testes sob carga. **Não publique estas edições como release estável sem revisão e testes adicionais.**

## Colaboração e segurança

As contribuições são bem-vindas! Abra uma [Issue](https://github.com/MoacirJr10/Manual-Atualizar/issues) ou um Pull Request com testes, documentação, sugestões e correções. **Não execute contribuições desconhecidas com sudo antes da revisão.** A branch `main` é protegida; esta prévia é proposta em uma branch e PR, sem alteração da versão estável.

Licença: [MIT](LICENSE).
