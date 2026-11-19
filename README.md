# Atualizar 3.1 — Central de manutenção do Ubuntu

![Versão 3.1](https://img.shields.io/badge/vers%C3%A3o-3.1-179c76) ![Ubuntu](https://img.shields.io/badge/SO-Ubuntu-E95420) ![Bash](https://img.shields.io/badge/Bash-script-4EAA25) ![Python](https://img.shields.io/badge/Python-3-3776AB) [![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue)](LICENSE)

O **Atualizar** reúne atualização de pacotes, manutenção, diagnóstico e acompanhamento de hardware em uma interface interativa no terminal. O projeto foi desenvolvido a partir de problemas reais de manutenção de um computador Ubuntu e prioriza transparência, confirmação de operações sensíveis e relatórios locais.

**[Manual completo em PDF](Atualizar-3.1-Manual.pdf)** · **[Código-fonte](atualizar-v3.1.sh)**

## Recursos

- Atualização APT, Snap e Flatpak; simulação APT e limpeza opcional.
- Diagnóstico de CPU, memória, armazenamento SMART, GPU, sensores e PWM.
- Kernel, metapacotes HWE, Kdump, MOK e Secure Boot.
- Serviços systemd, GNOME Keyring, AppArmor, rede e DNS.
- Monitoramento com dez amostras; testes opcionais de CPU e RAM.
- Backups privados de configurações; recuperação APT condicionada à confirmação.
- Histórico, comparação entre relatórios do mesmo modo e exportação TXT, HTML e JSON.

## Requisitos

Ubuntu, Bash, Python 3 (relatórios), terminal e acesso sudo para operações privilegiadas. Utilitários como `smartctl`, `sensors`, `nvidia-smi`, `stress-ng` e `memtester` são opcionais; algumas consultas dependem dos drivers e serviços disponíveis. O script não instala automaticamente utilitários ausentes.

Validado nos modos de consulta em Ubuntu 26.04.1 LTS, com Ryzen 5 7600X e RTX 3060. Há tratamento específico para a MSI MS-7E24; outros equipamentos podem apresentar sensores e resultados diferentes. Não há garantia de compatibilidade com todas as versões e configurações do Ubuntu.

## Instalação

Clone o repositório ou baixe os arquivos pelo botão **Code → Download ZIP**. Com Git:

```bash
git clone https://github.com/MoacirJr10/Manual-Atualizar.git
cd Manual-Atualizar
```

Confira o código antes de executar. Verifique a integridade e a sintaxe:

```bash
sha256sum -c SHA256SUMS
bash -n atualizar-v3.1.sh
bash atualizar-v3.1.sh --versao
```

Comece por um diagnóstico sem sudo:

```bash
bash atualizar-v3.1.sh --hardware --sem-sudo
```

Algumas informações serão omitidas sem privilégios. Para instalar o comando no seu usuário (se já existir `atualizar`, faça uma cópia antes):

```bash
mkdir -p ~/.local/bin
install -m 755 atualizar-v3.1.sh ~/.local/bin/atualizar
~/.local/bin/atualizar --versao
```

Se `~/.local/bin` estiver no PATH, basta executar `atualizar`. Caso contrário, use o caminho completo ou adicione a pasta ao PATH do seu shell. Nunca execute `sudo atualizar`: a ferramenta solicita elevação internamente quando necessário.

## Uso

```bash
atualizar
```

| Comando | Finalidade |
|---|---|
| `atualizar --diagnostico` | Diagnóstico completo |
| `atualizar --simular` | Simular APT com os índices locais |
| `atualizar --hardware` | Sensores, drivers e SMART |
| `atualizar --rede` | Rede e DNS |
| `atualizar --seguranca` | Consultas de segurança |
| `atualizar --kernel` | HWE, Kdump, MOK e logs |
| `atualizar --servicos` | Serviços e falhas de aplicativos |
| `atualizar --monitor` | Dez amostras de monitoramento |
| `atualizar --historico` | Relatórios recentes |
| `atualizar --comparar` | Comparar relatórios finalizados do mesmo modo |
| `atualizar --exportar` | Gerar HTML e JSON |
| `atualizar --atualizar` | Atualização real de pacotes |
| `atualizar --atualizar --limpeza` | Atualização com limpeza opcional |
| `atualizar --recuperacao` | Recuperação APT com confirmação |
| `atualizar --backup` | Copiar configurações para backup privado |
| `atualizar --testes` | Testes curtos de CPU e RAM com confirmação |
| `atualizar --ajuda` | Todas as opções |

## Relatórios e segurança

Os relatórios ficam na pasta de Downloads configurada pelo sistema, dentro de `Relatorios-atualizar/`. Os formatos de saída são TXT, HTML local e JSON. A classificação distingue achados normais, informativos, de atenção e críticos; um aviso não é, isoladamente, diagnóstico de defeito.

- Faça backup dos dados antes de atualizar, limpar ou reparar pacotes. Essas ações podem alterar programas e reiniciar serviços. Leia as confirmações.
- O programa não reinicia automaticamente o computador nem altera diretamente o GRUB, a BIOS, Secure Boot ou curvas de refrigeração. Não desativa AppArmor nem para/remove Nextcloud como correção de diagnóstico; uma atualização normal de Snap ainda pode atualizar aplicativos e reiniciar seus serviços.
- Testes de carga podem aquecer ou travar máquinas instáveis. Não substituem testes prolongados. Os backups de configurações não incluem todos os dados do sistema e podem conter segredos; mantenha-os privados.
- Os relatórios podem conter nomes de máquinas, IPs, aplicativos, caminhos e logs. Revise-os antes de compartilhar. Não publique relatórios brutos, backups ou credenciais.
- Os diagnósticos, exportação e monitoramento foram exercitados no ambiente original. Os modos de atualização real, recuperação, backup e testes sob carga da versão 3.1 ainda necessitam de validação prática adicional.

## Estrutura

```text
Manual-Atualizar/
├── README.md
├── atualizar-v3.1.sh
├── Atualizar-3.1-Manual.pdf
├── SHA256SUMS
├── LICENSE
├── CONTRIBUTING.md
└── .gitignore
```

## Contribuições são sempre bem-vindas!

O Atualizar é um projeto aberto à comunidade. Toda ajuda é bem-vinda, independentemente do seu nível de experiência. A ideia é evoluir a ferramenta em conjunto, tornando a manutenção do Ubuntu mais acessível, transparente e segura.

Você pode contribuir com sugestões de funcionalidades, correções de bugs, melhorias no código e na documentação, traduções ou testes em outras versões do Ubuntu e configurações de hardware.

- Abra uma [Issue](https://github.com/MoacirJr10/Manual-Atualizar/issues) para compartilhar ideias ou relatar problemas.
- Faça um fork e envie um [Pull Request](https://github.com/MoacirJr10/Manual-Atualizar/pulls) para propor melhorias.
- Consulte o [guia de contribuição](CONTRIBUTING.md) antes de enviar alterações e remova dados pessoais dos logs.

Se a ferramenta foi útil para você, uma estrela no repositório ou o compartilhamento com outros usuários também ajuda o projeto a crescer. Obrigado a todos que contribuírem!

## Licença

Distribuído sob a [licença MIT](LICENSE). Você pode usar, estudar, modificar e redistribuir o software, inclusive comercialmente, desde que preserve o aviso de copyright e o texto da licença conforme seus termos. O software é fornecido sem garantias.

## Autor

Desenvolvido por [MoacirJr10](https://github.com/MoacirJr10).
