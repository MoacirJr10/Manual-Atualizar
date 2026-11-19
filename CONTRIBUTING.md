# Como contribuir com o Atualizar

Toda ajuda é bem-vinda! Não é necessário ser desenvolvedor para participar.
Testes em outras máquinas, documentação, sugestões e relatos de problemas são contribuições valiosas.

## Relatar um problema ou sugerir uma melhoria

Abra uma [Issue](https://github.com/MoacirJr10/Manual-Atualizar/issues). Informe:

- versão do Ubuntu, kernel e versão do Atualizar;
- comando utilizado, comportamento esperado e comportamento observado;
- etapas para reproduzir e trecho relevante do relatório, se possível.

Remova nomes de usuários, endereços IP, nomes de máquinas, números de série, tokens, senhas e outros dados privados. Não envie backups, chaves ou relatórios brutos. Para uma possível vulnerabilidade, evite divulgar detalhes exploráveis em uma issue pública; procure primeiro contato privado com o mantenedor.

## Enviar alterações no código

1. Faça um fork do repositório.
2. Clone seu fork e crie uma branch para a alteração (`git switch -c melhoria/descricao`).
3. Faça mudanças pequenas, claras e documentadas.
4. Valide a sintaxe (`bash -n atualizar-v3.1.sh`) e teste inicialmente sem privilégios (`bash atualizar-v3.1.sh --hardware --sem-sudo`).
5. Para testes de operações que alteram o sistema, utilize uma máquina virtual ou ambiente descartável com backup. Não execute testes destrutivos em sistemas de terceiros.
6. Se alterar o script ou o manual, atualize os arquivos de documentação correspondentes e gere novamente `SHA256SUMS` com `sha256sum atualizar-v3.1.sh Atualizar-3.1-Manual.pdf > SHA256SUMS`. Não altere o número da versão oficial por conta própria.
7. Faça o commit, envie sua branch ao fork e abra um Pull Request descrevendo a mudança, os testes e as limitações.

## Princípios do projeto

- Preservar o controle do usuário: operações sensíveis exigem confirmação.
- Não aplicar alterações automáticas à BIOS, Secure Boot, GRUB, tensões, ventoinhas ou regras de segurança como parte do diagnóstico.
- Distinguir alertas de hardware confirmados de leituras suspeitas ou falta de dados.
- Manter relatórios locais, respeitar a privacidade e evitar dependências desnecessárias.
- Ser respeitoso, acolhedor e construtivo nas discussões.

Ao contribuir, espera-se que o material enviado possa ser distribuído sob a [licença MIT](LICENSE) do projeto. Envie somente material que você tem direito de licenciar.

Obrigado por colaborar!
