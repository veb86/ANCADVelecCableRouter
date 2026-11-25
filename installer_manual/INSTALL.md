# ANCADVelecCableRouter — ручная установка (AutoCAD 2020–2024, а также 2025)

Архив `ANCADVelecCableRouter-manual-install-v<версия>.zip` устанавливается **без инсталлятора и без прав
администратора**: все файлы размещаются только в профиле текущего пользователя
(`C:\Users\<имя>\AppData\Roaming`, он же `%APPDATA%`). AutoCAD сам загружает плагин из папки
`%APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle`.

## Состав архива

| Путь в архиве | Назначение |
| --- | --- |
| `AppData\Roaming\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle\PackageContents.xml` | описание пакета для автозагрузчика AutoCAD |
| `…\ANCADVelecCableRouter.bundle\Contents\AutoCAD2020-2024\VelecCableRouter.AutoCAD.dll` | плагин для **AutoCAD 2020, 2021, 2022, 2023, 2024** x64 (.NET Framework 4.8) |
| `…\ANCADVelecCableRouter.bundle\Contents\AutoCAD2020-2024\VelecCableRouter.Core.dll` | ядро трассировки (зависимость плагина) |
| `…\ANCADVelecCableRouter.bundle\Contents\AutoCAD2025\…` | те же файлы для AutoCAD 2025 x64 (.NET 8) |
| `install.cmd` | копирует папку `AppData` архива в профиль пользователя |
| `uninstall.cmd` | удаляет установленный пакет из профиля пользователя |
| `INSTALL.md` | эта инструкция |

AutoCAD сам выбирает нужную папку `Contents\…` по своей версии (`SeriesMin`/`SeriesMax` в
`PackageContents.xml`). Не перемещайте DLL отдельно от соседних файлов. Работает и в вертикальных
продуктах на базе AutoCAD (AutoCAD Electrical, Mechanical и т. п.) тех же версий.

## 1. Распаковка

1. Закройте AutoCAD.
2. Windows помечает скачанные файлы как полученные из интернета. Перед распаковкой откройте свойства
   ZIP-архива и установите флажок **«Разблокировать»** — иначе .NET может отказаться загружать DLL.
3. Распакуйте архив в любую временную папку.

## 2. Копирование файлов в профиль пользователя

**Вариант А — автоматически.** Запустите `install.cmd` двойным щелчком (права администратора не нужны).
Скрипт удалит прежнюю версию пакета (если она есть) и скопирует папку `AppData\Roaming` архива в `%APPDATA%`.

**Вариант Б — вручную.**

1. Нажмите `Win+R`, введите `%USERPROFILE%` и нажмите Enter — откроется `C:\Users\<имя>`.
2. Скопируйте туда папку `AppData` из архива и подтвердите слияние папок.

После копирования должны существовать файлы:

```text
%APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle\PackageContents.xml
%APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle\Contents\AutoCAD2020-2024\VelecCableRouter.AutoCAD.dll
%APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle\Contents\AutoCAD2020-2024\VelecCableRouter.Core.dll
```

## 3. Запуск AutoCAD

1. Запустите AutoCAD 2020–2024 (или 2025). Плагин загрузится автоматически, в командной строке появится
   сообщение `VelecCableRouter загружен…`.
2. Если появится предупреждение безопасности о загрузке `VelecCableRouter.AutoCAD.dll`, выберите
   **«Всегда загружать»** либо добавьте папку пакета в надёжные пути (`OPTIONS` → «Файлы» →
   «Надёжные папки» или системная переменная `TRUSTEDPATHS`):

   ```text
   %APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle\...
   ```

3. Выполните команду `VELEC_BUILD_CABLES` (построить кабели) или `VELEC_CLEAR_DEBUG` (удалить диагностику).

Если плагин не загрузился автоматически (например, `APPAUTOLOAD` = 0), выполните `NETLOAD` и выберите
`%APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle\Contents\AutoCAD2020-2024\VelecCableRouter.AutoCAD.dll`
(для AutoCAD 2025 — `…\Contents\AutoCAD2025\VelecCableRouter.AutoCAD.dll`). В поле имени файла можно
вставить путь целиком — `%APPDATA%` будет раскрыт.

## 4. Обновление

1. Закройте AutoCAD.
2. Распакуйте новую версию архива и запустите `install.cmd` (или повторите шаг 2, предварительно удалив
   старую папку `ANCADVelecCableRouter.bundle`).

## 5. Удаление

1. Закройте AutoCAD.
2. Запустите `uninstall.cmd` или удалите вручную папку

   ```text
   %APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle
   ```
