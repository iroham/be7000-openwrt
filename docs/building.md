# Сборка

[English](building.en.md)

Руками больше ничего не собирается. Всё делает один workflow в `.github/workflows/build.yml` на GitHub Actions.

- Запуск по кнопке (Actions, Build, Run workflow) собирает все пакеты из `config.buildinfo`, подписывает индексы ключом из секрета `APK_SIGNING_KEY` и пушит фид в ветку gh-pages.
- Пуш тега вида `v1.2.6` делает то же самое и вдобавок собирает прошивку, кладёт в архив установщик с инструкцией, считает суммы и создаёт Release. Текст релиза берётся из `docs/release-notes/<тег>.md`.
- Через артефакты Actions ничего не проходит, только git и Release. Компилятор кешируется через ccache между прогонами.
- Модули ядра публикуются в каталог с хешем конфига ядра, `feed/targets/qualcommbe/ipq95xx/<хеш>/packages/`. Образ при сборке вписывает свой хеш в `customfeeds.list`, поэтому старые образы продолжают находить подходящие модули, когда конфиг ядра меняется.

Если хочется собрать самому, порядок такой. Дерево kravasuper/openwrt на коммите 790d036a и фиды на дату из feeds-pins.txt. Патчи из patches в target/linux/qualcommbe/patches-6.18 и правки из patches/tree поверх дерева, описание в [patches.md](patches.md). В DTS платы два gpio-hog для TLMM6 (выход в ноль) и TLMM7 (выход в единицу), они нужны для нормального приёма на 5 ГГц. В профиль устройства kmod-ath11k-ahb. Фид awg-feed для AmneziaWG. Файл version в корне дерева с содержимым r20260623-790d036a, без него apk не соберёт base-files. overlay-files в files. В конфиге xiaomi_be7000, wpad-mbedtls вместо wpad-basic, luci-ssl. После make defconfig проверьте grep-ом, что нужные драйверы остались включёнными, потом make world. Собирать лучше в Docker на debian, исходники держать в томе Docker, а не на диске macOS, там регистронезависимая файловая система теряет файлы ядра.

```
grep -E "^(kmod-ath11k-ahb|kmod-ath12k|kmod-qcom-ppe|wpad-mbedtls|luci-ssl) " *.manifest
```

Образы можно разобрать скриптом scripts/ubi_extract.py (том 1 это squashfs).

Отладочные сборки по тегу `debug-*` выходят пре-релизом, фид не публикуют и собирают только образ, без пакетов-модулей для фида, поэтому занимают около получаса.
