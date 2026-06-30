@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ============================================================
:: EDIT THESE PATHS MANUALLY
:: ============================================================
set "MOD_DIR=C:\Program Files (x86)\Steam\steamapps\common\Halo The Master Chief Collection\halo4\mods\reflow\halo4\maps-spartanops"
set "GAME_DIR=C:\Program Files (x86)\Steam\steamapps\common\Halo The Master Chief Collection\halo4\maps"
:: ============================================================

:: Check for Administrator privileges
fltmc >nul 2>&1
if errorlevel 1 (
    echo This script must be run as Administrator.
    echo.
    echo Right-click the .bat file and select "Run as administrator".
    echo.
    pause
    exit /b 1
)

:: Check if folders exist
if not exist "!MOD_DIR!\" (
    echo Mod folder not found:
    echo !MOD_DIR!
    echo.
    pause
    exit /b 1
)

if not exist "!GAME_DIR!\" (
    echo Game folder not found:
    echo !GAME_DIR!
    echo.
    pause
    exit /b 1
)

call :CHECK_STATUS

echo.
echo ==========================================
echo Halo 4 Reflow Mod Manager
echo ==========================================
echo Current mod status: !MOD_STATUS!
echo.
echo [1] Install mod
echo [2] Remove mod
echo [3] Exit
echo.

choice /C 123 /M "Choose an option: "

if errorlevel 3 exit /b 0
if errorlevel 2 goto REMOVE_MOD
if errorlevel 1 goto INSTALL_MOD


:CHECK_STATUS
set "TOTAL_MOD_FILES=0"
set "LINKED_FILES=0"

pushd "!MOD_DIR!" >nul 2>&1
if errorlevel 1 (
    set "MOD_STATUS=Unknown - cannot access mod folder"
    exit /b 0
)

for %%F in (*.map) do (
    set /a TOTAL_MOD_FILES+=1
    set "GAME_FILE=!GAME_DIR!\%%~nxF"

    if exist "!GAME_FILE!" (
        fsutil reparsepoint query "!GAME_FILE!" >nul 2>&1
        if not errorlevel 1 (
            set /a LINKED_FILES+=1
        )
    )
)

popd

if "!TOTAL_MOD_FILES!"=="0" (
    set "MOD_STATUS=Unknown - no .map files found"
) else if "!LINKED_FILES!"=="0" (
    set "MOD_STATUS=Not installed"
) else if "!LINKED_FILES!"=="!TOTAL_MOD_FILES!" (
    set "MOD_STATUS=Installed"
) else (
    set "MOD_STATUS=Partially installed"
)

exit /b 0


:INSTALL_MOD
echo.
echo Installing mod...
echo.

pushd "!MOD_DIR!" >nul 2>&1
if errorlevel 1 (
    echo Failed to access mod folder:
    echo !MOD_DIR!
    echo.
    pause
    exit /b 1
)

dir /b /a-d "*.map" >nul 2>&1
if errorlevel 1 (
    echo No .map files found in the mod folder.
    echo.
    popd
    pause
    exit /b 1
)

for %%F in (*.map) do (
    set "MOD_FILE=%%~fF"
    set "FILE_NAME=%%~nxF"
    set "GAME_FILE=!GAME_DIR!\%%~nxF"
    set "BACKUP_FILE=!GAME_DIR!\%%~nxF.bak"
    set "SKIP_FILE=0"

    echo Processing: !FILE_NAME!

    if exist "!GAME_FILE!" (
        fsutil reparsepoint query "!GAME_FILE!" >nul 2>&1

        if errorlevel 1 (
            if exist "!BACKUP_FILE!" (
                echo Backup already exists. Skipping backup:
                echo !BACKUP_FILE!
            ) else (
                echo Backing up original file...
                ren "!GAME_FILE!" "%%~nxF.bak"
            )
        ) else (
            echo Symbolic link already exists. Nothing to do.
            set "SKIP_FILE=1"
        )
    )

    if "!SKIP_FILE!"=="0" (
        if exist "!GAME_FILE!" (
            echo Cannot create symbolic link because a file still exists:
            echo !GAME_FILE!
        ) else (
            echo Creating symbolic link...
            mklink "!GAME_FILE!" "!MOD_FILE!"
        )
    )

    echo.
)

popd

echo Installation finished.
pause
exit /b 0


:REMOVE_MOD
echo.
echo Removing mod...
echo.

pushd "!MOD_DIR!" >nul 2>&1
if errorlevel 1 (
    echo Failed to access the mod folder:
    echo !MOD_DIR!
    echo.
    pause
    exit /b 1
)

dir /b /a-d "*.map" >nul 2>&1
if errorlevel 1 (
    echo No .map files found in the mod folder.
    echo.
    popd
    pause
    exit /b 1
)

for %%F in (*.map) do (
    set "FILE_NAME=%%~nxF"
    set "GAME_FILE=!GAME_DIR!\%%~nxF"
    set "BACKUP_FILE=!GAME_DIR!\%%~nxF.bak"

    echo Processing: !FILE_NAME!

    if exist "!GAME_FILE!" (
        fsutil reparsepoint query "!GAME_FILE!" >nul 2>&1

        if errorlevel 1 (
            echo Game file exists but is not a symbolic link. It will not be deleted.
        ) else (
            echo Removing symbolic link...
            del /f /q "!GAME_FILE!" >nul 2>&1
        )
    ) else (
        echo No symbolic link found in the game folder.
    )

    if exist "!BACKUP_FILE!" (
        if exist "!GAME_FILE!" (
            echo Cannot restore backup because a file with the original name already exists:
            echo !GAME_FILE!
        ) else (
            echo Restoring original file...
            ren "!BACKUP_FILE!" "%%~nxF"
        )
    ) else (
        echo No backup file found.
    )

    echo.
)

popd

echo Removal finished.
pause
exit /b 0
