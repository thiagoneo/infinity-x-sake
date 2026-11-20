# Infinity X para o Zenfone 8 (sake)

Scripts e patches para compilar o [Project Infinity X](https://github.com/ProjectInfinity-X)
(Android 17) para o ASUS Zenfone 8 (`sake`, `ASUS_I006D`), com base na árvore
do LineageOS 24.0. Build não oficial.

Duas variantes, ambas sem mudanças no Infinity (só o necessário para o
aparelho):

| Variante | O que é |
|---|---|
| `vanilla` | Infinity X sem Google (`WITH_GAPPS=false`) |
| `gapps` | Infinity X com os apps do Google (`WITH_GAPPS=true`, `vendor/pixel/gms`) |

## O que muda em relação ao LineageOS

A árvore do aparelho é um fork de
[LineageOS/android_device_asus_sake](https://github.com/LineageOS/android_device_asus_sake)
com 4 commits, na branch `17` de
[thiagoneo/android_device_asus_sake](https://github.com/thiagoneo/android_device_asus_sake)
(os mesmos commits estão em `device-tree/`):

1. adaptação ao Infinity X (`infinity_sake.mk`, informações de "Sobre o telefone");
2. `armv8-2a` para a segunda arquitetura (exigido pelo build do Infinity);
3. configuração opcional para compilar com pouca RAM (`lowmem.mk`);
4. a variante (com ou sem Google) é escolhida na hora da build.

Kernel e arquivos proprietários são os do LineageOS
(`LineageOS/android_kernel_asus_sm8350` e `TheMuppets/proprietary_vendor_asus_sake`),
incluindo o firmware (33.0210.0210.296), gravado a cada instalação, como no
LineageOS.

## Estrutura

```
.
├── config.sh                 # caminhos, usuário do GitHub, -j, limites
├── local_manifests/
│   └── sake.xml.in           # modelo do local manifest (árvore + kernel + blobs)
├── patches/                  # patches em projetos do source (reaplicados após o sync)
│   └── build/soong/          # deixa o GOGC chegar ao soong_build (menos RAM)
├── device-tree/              # commits do fork da árvore
├── scripts/
│   ├── check-build-reqs.sh   # verificação inicial da máquina
│   ├── sync.sh               # repo sync + reaplica patches + checagens
│   ├── build.sh              # checagens + build + copia artefatos / resume erros
│   ├── update-tree.sh        # traz atualizações do LineageOS para o fork
│   ├── cleanup.sh            # limpeza: zips, builds/, logs/, ccache, git gc, snapshots
│   └── lowmem.sh             # zram + earlyoom off (on/off, com sudo)
├── builds/AAAA-MM-DD-<variante>/   # zip, boot.img, vendor_boot.img, SHA256SUMS
└── logs/                     # build-*.log e errors-*.txt
```

`patches/<caminho>/*.patch` é aplicado no projeto `<caminho>` do source.
`variants/<variante>/patches/<caminho>/` (não usado neste repositório) funciona
igual, mas só entra na build daquela variante.

Ajustes pessoais podem ir num `config.local.sh` (fora do git), lido depois do
`config.sh`.

## Primeira vez

1. Source do Infinity X (veja as instruções do projeto), em `SRC` do
   `config.sh` (padrão: `~/android/infinity`):

   ```
   repo init -u https://github.com/ProjectInfinity-X/manifest -b 17 --git-lfs --depth=1
   ```

2. `bash scripts/check-build-reqs.sh` para conferir a máquina.
3. `bash scripts/sync.sh` (gera o local manifest, sincroniza e aplica os patches).

Para usar o seu próprio fork da árvore: faça o fork do LineageOS, aplique os
commits de `device-tree/` na branch `17` e mude `GITHUB_USER` no `config.sh`.

## Rotina de build

Com ~16 GB de RAM, compile fora da sessão gráfica (TTY, Ctrl+Alt+F3), em bash:

```
sudo systemctl isolate multi-user.target
sudo ZRAM_SIZE=24G bash scripts/lowmem.sh on
tmux new -s build
bash scripts/sync.sh
bash scripts/build.sh vanilla     # ou: gapps
```

Depois:

```
sudo bash scripts/lowmem.sh off
sudo systemctl isolate graphical.target
```

Se a build falhar, o resumo fica em `logs/errors-*.txt`. Rode só
`bash scripts/build.sh` de novo (sem sync): o que já foi compilado é
reaproveitado.

- Depois do `lunch`, o `build.sh` confere os pacotes da variante (sem Google
  na vanilla, Play Store na gapps).
- As variantes usam o mesmo `out/`. Ao trocar de variante, o `build.sh` roda
  `m installclean` e o Soong refaz a análise: conte ~1–1,5 h a mais.
- `LOWMEM=true` (`config.sh`) liga o `lowmem.mk`, `GOGC=30` e
  `ALLOW_MISSING_DEPENDENCIES`. Com 32 GB de RAM ou mais, use `LOWMEM=false`.

## Instalação

Primeira vez (ou ao trocar de variante, com formatação dos dados):

1. `fastboot flash vendor_boot vendor_boot.img` e `fastboot flash boot boot.img`
   (o recovery vem no `boot.img`);
2. no recovery: *Apply update* → *Apply from ADB*, `adb sideload <zip>`;
3. *Format data / factory reset*.

Atualizações da mesma variante: app Atualizador → ⋮ → *Atualização local*,
escolhendo o zip (sem perder dados).

Trocar entre vanilla e gapps exige formatar os dados.

## Quando o LineageOS atualizar a árvore do sake

O `sync.sh` avisa. Então `bash scripts/update-tree.sh`: faz rebase dos
commits sobre o upstream e envia ao fork. Se houver conflito, desfaz tudo.

## Limpeza

```
bash scripts/cleanup.sh                 # zips antigos, builds/ e logs/ antigos, ccache
bash scripts/cleanup.sh --gc            # + git gc no source (lento)
bash scripts/cleanup.sh --snapshots     # + snapshots do snapper que contêm as pastas do port
```

Cada etapa mostra o que vai apagar e pede confirmação. Quantidades em
`config.sh` (`KEEP_BUILDS`, `KEEP_LOG_DAYS`, `KEEP_SNAPSHOTS`).

## Notas

- Se um patch deixar de encaixar após um sync, o script para com erro e não
  deixa nada pela metade.
- As builds são assinadas com as test-keys do AOSP.
