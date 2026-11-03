# BLE SKUD iOS

Тестовый iOS-клиент СКУД Уфанет. Сборка в облаке GitHub Actions.

## Шаги
1. github.com/new — создай пустой репо (public = Actions бесплатно).
2. git init && git branch -M main
3. git add . && git commit -m init
4. git remote add origin https://github.com/USER/REPO.git
5. git push -u origin main
6. Actions -> дождись "Build iOS IPA" (~5 мин) -> скачай BleSkud-unsigned.ipa
7. Sideloadly (Windows) -> установи с бесплатным Apple ID. 7 дней, потом переподпись.

## BLE_PASS
В коде не нужен. Если требуется bonding — iOS спросит PIN, введи 12345.
