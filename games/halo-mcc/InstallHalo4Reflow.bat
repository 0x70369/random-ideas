@echo off
setlocal EnableExtensions
:: Install or remove the Halo 4 Reflow Spartan Ops maps as symbolic links.
:: Run as administrator: the game folder is under Program Files.

:: Edit STEAM if MCC is in another Steam library.
set "STEAM=C:\Program Files (x86)\Steam\steamapps\common"
set "H4=%STEAM%\Halo The Master Chief Collection\halo4"
set "MOD_DIR=%H4%\mods\reflow\halo4\maps-spartanops"
set "GAME_DIR=%H4%\maps"

fltmc >nul 2>&1 || (echo Run this script as administrator.& goto END)
if not exist "%MOD_DIR%\*.map" (echo No .map files in "%MOD_DIR%".& goto END)
if not exist "%GAME_DIR%\" (echo Game folder not found: "%GAME_DIR%".& goto END)

set /a TOTAL=0, LINKED=0
for %%F in ("%MOD_DIR%\*.map") do (
    set /a TOTAL+=1
    call :IS_LINK "%GAME_DIR%\%%~nxF" && set /a LINKED+=1
)
echo Reflow maps linked: %LINKED% of %TOTAL%.
choice /c IRQ /m "Install, Remove or Quit"
if errorlevel 3 goto END
if errorlevel 2 goto REMOVE

for %%F in ("%MOD_DIR%\*.map") do call :LINK "%%~fF" "%GAME_DIR%\%%~nxF"
goto END

:REMOVE
for %%F in ("%MOD_DIR%\*.map") do call :RESTORE "%GAME_DIR%\%%~nxF"

:END
pause
exit /b

:: %1 = mod map, %2 = game map. Back up the original, then link.
:LINK
call :IS_LINK %2 && (echo Already linked: %~nx2& exit /b)
if exist %2 if not exist "%~2.bak" (echo Backup: %~nx2.bak& ren %2 "%~nx2.bak")
if exist %2 (echo Skipped, %~nx2 and its backup both exist.& exit /b)
mklink %2 %1
exit /b

:: %1 = game map. Remove the link, then restore the original.
:RESTORE
call :IS_LINK %1 && (echo Removed link: %~nx1& del %1)
if not exist "%~1.bak" exit /b
if exist %1 (echo Kept %~nx1.bak: %~nx1 is not a link.& exit /b)
echo Restored: %~nx1
ren "%~1.bak" "%~nx1"
exit /b

:IS_LINK
fsutil reparsepoint query %1 >nul 2>&1
exit /b
