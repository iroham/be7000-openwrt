# Сборка

[English](building.en.md)

Руками больше ничего не собирается. Всё делает один workflow в `.github/workflows/build.yml` на GitHub Actions.

- Запуск по кнопке (Actions, Build, Run workflow) собирает все пакеты из `config.buildinfo`, подписывает индексы ключом из секрета `APK_SIGNING_KEY` и пушит фид в ветку gh-pages.
- Пуш тега вида `v1.2.6` делает то же самое и вдобавок собирает прошивку, кладёт в архив установщик с инструкцией, считает суммы и создаёт Release. Текст релиза берётся из `docs/release-notes/<тег>.md`.
- Через артефакты Actions ничего не проходит, только git и Release. Компилятор кешируется через ccache между прогонами.
- Модули ядра публикуются в каталог с хешем конфига ядра, `feed/targets/qualcommbe/ipq95xx/<хеш>/packages/`. Образ при сборке вписывает свой хеш в `customfeeds.list`, поэтому старые образы продолжают находить подходящие модули, когда конфиг ядра меняется.

Если хочется собрать самому, порядок такой, он же в `.github/workflows/build.yml`. Дерево openwrt/openwrt на коммите из patches/port/BASE, поверх него `git am patches/port/*.patch`, это порт kravasuper. Фиды на коммитах из feeds-pins.txt. Патчи ядра из patches в target/linux/qualcommbe/patches-6.18, патчи ath12k из patches/mac80211-ath12k в package/kernel/mac80211/patches/ath12k, патчи mac80211 из patches/mac80211-subsys в package/kernel/mac80211/patches/subsys, правки дерева из patches/tree через patch -p1, описание в [patches.md](patches.md). Файл version в корне дерева с содержимым r20260929-d958caf, без него apk не соберёт base-files. overlay-files в files, awg-feed и luci-theme-nimbus рядом. Конфиг из config.buildinfo, потом make defconfig и make world. Собирать лучше в Docker на debian, исходники держать в томе Docker, а не на диске macOS, там регистронезависимая файловая система теряет файлы ядра. Если меняли конфиг ядра, пересоберите и внешние модули (mac80211, amneziawg), иначе они останутся собранными под старое ядро.

```
grep -E "^(kmod-ath11k-ahb|kmod-ath12k|kmod-qcom-ppe|wpad-mbedtls|luci-ssl) " *.manifest
```

Образы можно разобрать скриптом scripts/ubi_extract.py (том 1 это squashfs).

Отладочные сборки по тегу `debug-*` выходят пре-релизом, фид не публикуют и собирают только образ, без пакетов-модулей для фида, поэтому занимают около получаса.
