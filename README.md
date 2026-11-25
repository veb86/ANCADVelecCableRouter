# ANCADVelecCableRouter

Плагин автоматической трассировки кабелей для AutoCAD 2020–2025: порт алгоритма анализа топологии трасс из ZCAD
(`uzvcom.pas`, функции `getListSuperline` и `graphBulderFunc`) и прокладка 2D-полилиний кабелей с XDATA
по контракту BobrovXDATA v2.

![Пример результата](docs/screenshots/sample-plan.png)

*Результат `examples/VelecCableRouter.Sample`: серое — трассы (SuperLine), цветное — построенные кабели по группам,
пунктир — виртуальное ребро стояка Ст-1, красный крест — устройство без пути (ошибка в отчёте).*

## Состав решения `VelecCableRouter.sln`

| Проект | Назначение |
|---|---|
| `src/VelecCableRouter.Core` | `netstandard2.0`, без зависимостей от AutoCAD и UI: чтение BobrovXDATA v2, модель чертежа, построение графа, Дейкстра, сборка полилиний, отчёт и план диагностической графики. |
| `src/VelecCableRouter.AutoCAD` | Плагин: `IExtensionApplication`, команды, чтение примитивов DWG, запись полилиний и XDATA в одной транзакции. `net48` (AutoCAD 2020–2024, пакет `AutoCAD.NET` 23.1.0) и `net8.0-windows` (AutoCAD 2025, `AutoCAD.NET` 25.0.1). Сборки Autodesk берутся из официальных NuGet-пакетов и в выходной каталог не копируются. |
| `tests/VelecCableRouter.Core.Tests` | xUnit-тесты ядра. |
| `examples/VelecCableRouter.Sample` | Консольный пример: прогоняет весь алгоритм на тестовом плане без AutoCAD и пишет отчёт, XDATA кабелей и SVG. |

## Установка (AutoCAD 2020–2024)

В каждом [выпуске](../../releases) есть архив `ANCADVelecCableRouter-manual-install-v<версия>.zip`. Он
устанавливается **без инсталлятора и без прав администратора** — все файлы размещаются только в профиле
пользователя (`%APPDATA%`):

- AutoCAD 2020–2024 (а также 2025) — `%APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle`,
  плагин загружается автоматически при запуске AutoCAD.

Распакуйте архив и запустите `install.cmd` (или скопируйте папку `AppData` архива в `%USERPROFILE%`);
удаление — `uninstall.cmd`. Подробная инструкция — [installer_manual/INSTALL.md](installer_manual/INSTALL.md)
(она же лежит в архиве).

Структура пакета:

```text
ANCADVelecCableRouter.bundle\
  PackageContents.xml                        ← installer_acad/PackageContents.xml
  Contents\AutoCAD2020-2024\                 ← net48: SeriesMin R23.1 (2020) … SeriesMax R24.3 (2024)
    VelecCableRouter.AutoCAD.dll
    VelecCableRouter.Core.dll
  Contents\AutoCAD2025\                      ← net8.0-windows: R25.0 (2025)
    VelecCableRouter.AutoCAD.dll, VelecCableRouter.Core.dll, VelecCableRouter.AutoCAD.deps.json
```

Также в выпуске есть архивы `ANCADVelecCableRouter-AutoCAD2020-2024-v<версия>.zip` и
`ANCADVelecCableRouter-AutoCAD2025-v<версия>.zip` с DLL для ручной загрузки через `NETLOAD` и
`release-manifest.txt` с SHA256.

### Как выпустить новую версию

1. Увеличьте `<Version>` в `Directory.Build.props` и `AppVersion` в `installer_acad/PackageContents.xml`
   (CI проверяет, что они совпадают).
2. Слейте изменения в `main`: workflow `Build and test` соберёт плагин, упакует и проверит архивы, проверит
   `install.cmd`/`uninstall.cmd` и опубликует выпуск `v<версия>` (если его ещё нет). Выпуск также можно
   создать тегом `v<версия>` или ручным запуском workflow.

Локально (PowerShell 7, Windows или Linux):

```powershell
./scripts/package-release.ps1          # сборка и архивы в release/v<версия>/
./scripts/test-release-package.ps1     # проверка состава архивов, PackageContents.xml и DLL
./scripts/test-manual-install.ps1      # только Windows: install.cmd/uninstall.cmd во временном %APPDATA%
```

## Сборка и тесты

```bash
dotnet test tests/VelecCableRouter.Core.Tests          # тесты ядра (любая ОС, .NET 8 SDK)
dotnet build src/VelecCableRouter.AutoCAD -c Release    # плагин (Windows; на Linux тоже собирается)
dotnet run --project examples/VelecCableRouter.Sample -- sample-output
```

Сборка AutoCAD 2024 API: `dotnet build src/VelecCableRouter.AutoCAD -c Release -f net48 -p:AutoCadNet48ApiVersion=24.3.0`.

Загрузка в AutoCAD: `NETLOAD` → `bin/Release/net48/VelecCableRouter.AutoCAD.dll` (2020–2024) или
`bin/Release/net8.0-windows/VelecCableRouter.AutoCAD.dll` (2025). Рядом должен лежать `VelecCableRouter.Core.dll`.
Для сборки `net48` нужен установленный .NET Framework 4.8 (стандартен для Windows 10 1903+ и Windows 11).

## Команды

### `VELEC_BUILD_CABLES`

1. Берёт предварительно выбранные объекты (PICKFIRST) или запрашивает выбор (`Editor.GetSelection`).
2. Предлагает параметры (Enter — построить):
   * `ДОпуск` — Epsilon графа, по умолчанию `0.5`;
   * `ДИагностика` — `Да`/`Нет` (по умолчанию `Нет`): рисует граф на слоях `VELEC_DEBUG_<имя суперлинии>`
     (вершины — окружности: зелёные у устройств, жёлтые — пересечения и концы трасс; рёбра — голубые линии,
     рёбра стояков — пурпурные; ошибки — красные маркеры с текстом); прежняя графика этого слоя заменяется;
   * `Слой` — `Текущий` (по умолчанию) или `Трассы` (слой первого отрезка трассы кабеля).
   Значения запоминаются до конца сеанса AutoCAD.
3. В одной транзакции создаёт все полилинии кабелей, регистрирует `BobrovXDATA` в RegAppTable (если его нет) и
   записывает XDATA v2:

   ```
   (1001 . "BobrovXDATA") (1070 . 2)
   (1000 . "DEVICE_ID") (1000 . "<новый GUID>") (1000 . "TEMPLATE") (1000 . "Cable")
   (1000 . "NMO_Name") (1000 . "<суперлиния>") (1000 . "SuperLineName") (1000 . "<суперлиния>")
   (1000 . "HeadDeviceName") (1000 . "<головное>") (1000 . "GroupName") (1000 . "<группа>")
   ```
4. Выводит отчёт по каждой суперлинии: имя, число вершин и рёбер, групп, кабелей, предупреждения и ошибки
   (с handle объекта и координатой), итог.

Пример отчёта (`examples/VelecCableRouter.Sample`):

```
Суперлиния «ОПС»: вершин 9, рёбер 7, групп 2, кабелей 3, предупреждений 0, ошибок 1.
  Группа «ППК-1» / «ШС1»: устройств 3, полилиний 2, длина 85.
  Группа «ППК-1» / «ШС2»: устройств 2, полилиний 1, длина 65.
  Ошибка: Группа «ППК-1» / «ШС2»: нет пути от «ППК-1» до устройства «ИП-5». [handle 208] (70; 25)
Суперлиния «ЭС»: вершин 6, рёбер 5, групп 1, кабелей 2, предупреждений 0, ошибок 0.
  Группа «ЩР-1» / «Гр.1»: устройств 2, полилиний 2, длина 80.
Итого: суперлиний 2, кабелей 5, предупреждений 0, ошибок 1.
```

### `VELEC_CLEAR_DEBUG`

Удаляет все примитивы со слоёв `VELEC_DEBUG_*` во всех листах и в пространстве модели (заблокированные слои
предварительно разблокируются). Сами пустые слои остаются — их удаляет `_PURGE`.

## Входные данные

* **Трасса (SuperLine)** — `Line`, `Polyline` или `Polyline2d` с `TEMPLATE = SuperLine` и `NMO_Name`
  (имя суперлинии). Полилиния разбивается на отрезки (замкнутая — с замыкающим). Объект без `NMO_Name`
  игнорируется с предупреждением; дуги заменяются хордами с предупреждением.
* **Устройство (Device)** — `BlockReference` с `TEMPLATE = Device`. Подключения — повторяющиеся поля
  `conn_<n>_SuperLine`, `conn_<n>_HeadDevice`, `conn_<n>_Group` (допускаются и `..._SuperLineName`,
  `..._HeadDeviceName`, `..._GroupName`) и/или скалярные `SuperLineName`, `HeadDeviceName`, `GroupName`.
  Точка подключения — мировая координата вложенного блока `CONNECTOR_POINT`/`CONNECTOR_SQUARE`, атрибута
  с таким тегом или точки на слое с таким именем (рекурсивный поиск по определению блока с учётом
  `BlockTransform`), иначе `BlockReference.Position`; Z отбрасывается. Необязательные `RiserName` и
  `Elevation` описывают стояк.
* Формат XDATA определяется как в acadPaletteSetXDATA: нет секции — объект не участвует; v1 (без `(1070 . 2)`) —
  предупреждение, объект не читается; версия > 2 — читается с предупреждением. Идентификаторы
  регистронезависимы.

Алгоритм, отличия от ZCAD и принятые допущения описаны в [docs/algorithm.md](docs/algorithm.md).
Тестовый чертёж для AutoCAD создаёт [examples/velec-test-drawing.lsp](examples/velec-test-drawing.lsp).
