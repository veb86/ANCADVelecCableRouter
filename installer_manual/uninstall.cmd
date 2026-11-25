@echo off
chcp 65001 >nul
setlocal

rem ANCADVelecCableRouter: removes the per-user installation made by install.cmd.
rem "uninstall.cmd /quiet" does not wait for a key press (used by CI).

set "PAUSE_AT_END=1"
if /i "%~1"=="/quiet" set "PAUSE_AT_END="

if "%APPDATA%"=="" (
    echo Переменная APPDATA не задана.
    goto :fail
)

set "BUNDLE=%APPDATA%\Autodesk\ApplicationPlugins\ANCADVelecCableRouter.bundle"
if not exist "%BUNDLE%" (
    echo ANCADVelecCableRouter не установлен.
    goto :done
)

rmdir /s /q "%BUNDLE%"
if exist "%BUNDLE%" (
    echo Не удалось удалить плагин. Закройте AutoCAD и запустите uninstall.cmd снова.
    goto :fail
)
echo Удалено: %BUNDLE%

:done
echo Готово.
if defined PAUSE_AT_END pause
exit /b 0

:fail
if defined PAUSE_AT_END pause
exit /b 1
