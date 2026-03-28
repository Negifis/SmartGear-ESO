@echo off
echo Packaging SmartGear for ESOUI...

set ADDON_NAME=SmartGear
set VERSION=1.0.0
set OUTDIR=%~dp0\release
set ZIPNAME=%ADDON_NAME%-%VERSION%.zip

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

:: Create temp staging folder
set STAGE=%OUTDIR%\%ADDON_NAME%
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%"
mkdir "%STAGE%\Localization"

:: Copy addon files (no updater, no cache, no .claude)
copy "%~dp0SmartGear.txt"     "%STAGE%\"
copy "%~dp0SmartGear.lua"     "%STAGE%\"
copy "%~dp0Core.lua"          "%STAGE%\"
copy "%~dp0MetaData.lua"      "%STAGE%\"
copy "%~dp0TooltipHook.lua"   "%STAGE%\"
copy "%~dp0UpgradeAlert.xml"  "%STAGE%\"
copy "%~dp0UpgradeAlert.lua"  "%STAGE%\"
copy "%~dp0Settings.lua"      "%STAGE%\"
copy "%~dp0Localization\en.lua" "%STAGE%\Localization\"
copy "%~dp0Localization\ru.lua" "%STAGE%\Localization\"

:: Create ZIP (requires PowerShell 5+)
pushd "%OUTDIR%"
powershell -Command "Compress-Archive -Path '%ADDON_NAME%' -DestinationPath '%ZIPNAME%' -Force"
popd

:: Cleanup staging
rmdir /s /q "%STAGE%"

echo.
echo Done! Package: %OUTDIR%\%ZIPNAME%
echo Upload this ZIP to https://www.esoui.com/downloads/filecpl.php
pause
