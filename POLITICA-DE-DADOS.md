# Política de dados

Segue a política de assets do VIctory upstream (`docs/asset-policy.md`, regra nº 1): **nada do jogo é guardado neste repositório.**

## Não pode entrar, em nenhuma forma

- Assets do título: modelos, texturas, shaders, áudio, vídeo, texto, arquivos `.rpf` e outros pacotes.
- O executável do título ou qualquer parte dele: seções, strings, tabelas, recursos.
- Derivados: código descompilado ou disassembly do título, dumps de shader, tabelas extraídas, screenshots, gravações, capturas RenderDoc/PIX.
- Binários das builds: `.exe`, `.dll`, `.pdb`, `.lib`, caches de shader e de pipeline.
- Logs brutos (`*.stderr`, `*.stdout`, `.log`, `.etl`, dumps). Do log sai só o número agregado.
- Dados pessoais: nome real, e-mail, caminhos com nome de usuário, IDs de hardware.

## Pode entrar

- Identidade de build: hash do executável (SHA-256 ou BLAKE3) e CodeView GUID/age do PDB.
- Offsets e RVAs de funções, com o nome do símbolo do VIctory (código aberto) ou um nome nosso.
- Números agregados: mediana, p95, contagens, médias, máximos, tabelas pequenas em CSV.
- Variáveis de ambiente e configuração do runtime (`VICTORY_*`).
- Relatórios em Markdown, scripts próprios de medição e conversão, dados sintéticos gerados por esses scripts.
- Referências a linhas do fonte do VIctory ou do fork (`host.rs:9313`), que é código aberto.

Na dúvida, não envie. Descreva o achado em palavras e cite o offset.

## Como a regra é aplicada

1. O `.gitignore` funciona como lista de permissão: ignora tudo e libera só `.md`, `.yml`, `.yaml`, `.json`, `.csv`, `.ps1`, `.py` e `.toml`. `harness.toml` e `victory.toml`, que contêm caminhos da máquina, ficam de fora.
2. `scripts/Test-RepoContent.ps1` recusa extensões fora da lista, binários, arquivos acima de 512 KiB, sequências longas de hex ou base64, listagens de disassembly, e-mails e caminhos de perfil de usuário do Windows.
3. O workflow `checagem-conteudo` roda o mesmo script em todo push e PR.

## Se algo escapar

Um commit de correção não basta. Reescreva o histórico (`git filter-repo --path <arquivo> --invert-paths`), force o push e peça a todos que clonem de novo. Avise na Issue de R00.
