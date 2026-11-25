@echo off
chcp 65001 >nul
setlocal

rem ANCADVelecCableRouter: per-user installation, administrator rights are not required.
rem Copies AppData\Roaming from the archive into %APPDATA% of the current user.
rem "install.cmd /quiet" does not wait for a key press (used by CI).

set "PAUSE_AT_END=1"
if /i "%~1"=="/quiet" set "PAUSE_AT_END="

set "SOURCE=%~dp0AppData\Roaming"
set "BUNDLE=%APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle"
if not exist "%SOURCE%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle\PackageContents.xml" (
    echo Не найдена папка AppData рядом с install.cmd. Распакуйте архив полностью.
    goto :fail
)
if "%APPDATA%"=="" (
    echo Переменная APPDATA не задана.
    goto :fail
)

rem Files of an older version are removed so that no stale DLL stays in the bundle.
rem Paths are not echoed inside ( ) blocks: a ')' in the user name would end the block.
if exist "%BUNDLE%" (
    rmdir /s /q "%BUNDLE%"
    if exist "%BUNDLE%" (
        echo Не удалось заменить прежнюю версию плагина. Закройте AutoCAD и запустите install.cmd снова.
        goto :fail
    )
)

echo Установка ANCADVelecCableRouter в %APPDATA% ...
robocopy "%SOURCE%" "%APPDATA%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
if errorlevel 8 (
    echo Ошибка копирования. Закройте AutoCAD и запустите install.cmd снова.
    goto :fail
)

echo.
echo Готово. AutoCAD 2020-2025 загрузит плагин автоматически при следующем запуске:
echo   %BUNDLE%
echo Команды: VELEC_BUILD_CABLES, VELEC_CLEAR_DEBUG. Подробности - в файле INSTALL.md.
if defined PAUSE_AT_END pause
exit /b 0

:fail
if defined PAUSE_AT_END pause
exit /b 1
