@echo off
setlocal enabledelayedexpansion
title MK Suite - Installation et creation du .exe
color 0E

echo ============================================
echo   MK SUITE - Installation automatique
echo ============================================
echo.

echo [1/4] Recherche d'une version de Python compatible...
echo (Python 3.14 a un bug connu qui casse les boutons dans ce type
echo  de logiciel - on cherche donc une version stable a la place)
echo.

set PY_CMD=

for %%V in (3.13 3.11 3.12 3.10) do (
    if "!PY_CMD!"=="" (
        py -%%V --version >nul 2>&1
        if not errorlevel 1 (
            set PY_CMD=py -%%V
            echo Trouve : Python %%V
        )
    )
)

if "!PY_CMD!"=="" (
    REM Aucune version pinnee trouvee : on prend celle par defaut, sauf si c'est la 3.14
    py --version >nul 2>&1
    if not errorlevel 1 (
        for /f "tokens=2" %%v in ('py --version 2^>^&1') do set FOUND_VER=%%v
        echo !FOUND_VER! | findstr /b "3.14" >nul
        if not errorlevel 1 (
            echo.
            echo ERREUR : Seul Python 3.14 a ete trouve sur ton PC.
            echo Cette version a un bug connu qui empeche les boutons de
            echo fonctionner dans MK Suite ^(ce n'est pas un bug de MK Suite,
            echo c'est un bug de Python 3.14 lui-meme, deja signale aux
            echo developpeurs de Python^).
            echo.
            echo SOLUTION : installe Python 3.13 via ce lien direct :
            echo https://www.python.org/ftp/python/3.13.13/python-3.13.13-amd64.exe
            echo en cochant bien "Add python.exe to PATH", puis relance ce script.
            pause
            exit /b 1
        )
        set PY_CMD=py
        echo Trouve : Python !FOUND_VER!
    )
)

if "!PY_CMD!"=="" (
    REM Dernier recours : la commande "python" au lieu de "py" (rare sous Windows,
    REM mais possible selon comment Python a ete installe)
    python --version >nul 2>&1
    if not errorlevel 1 (
        for /f "tokens=2" %%v in ('python --version 2^>^&1') do set FOUND_VER2=%%v
        echo !FOUND_VER2! | findstr /b "3.14" >nul
        if errorlevel 1 (
            set PY_CMD=python
            echo Trouve : Python !FOUND_VER2!
        )
    )
)

if "!PY_CMD!"=="" (
    echo ERREUR : Python introuvable. Installe-le via ce lien direct :
    echo https://www.python.org/ftp/python/3.13.13/python-3.13.13-amd64.exe
    echo ^(coche bien "Add python.exe to PATH"^) puis relance ce script.
    pause
    exit /b 1
)
echo OK - on utilise : !PY_CMD!
echo.

echo [2/4] Installation des dependances...
!PY_CMD! -m pip install -r requirements.txt --quiet
if errorlevel 1 (
    echo ERREUR pendant l'installation des dependances.
    pause
    exit /b 1
)
echo OK
echo.

echo [3/4] Test rapide du logiciel avant compilation...
echo (Ferme la fenetre MK Suite qui va s'ouvrir pour continuer)
!PY_CMD! main.py
echo.

echo [4/4] Compilation en .exe (peut prendre 1 a 3 minutes)...
!PY_CMD! -m PyInstaller --name "MK_Suite" --windowed --onefile ^
    --icon="assets\icon.ico" ^
    --add-data "assets\icon.ico;assets" ^
    --add-data "..\assets\images\logo.png;assets" ^
    --hidden-import "PIL._tkinter_finder" ^
    --distpath "dist" ^
    main.py

if errorlevel 1 (
    echo ERREUR pendant la compilation.
    pause
    exit /b 1
)

echo.
echo ============================================
echo   TERMINE !
echo   Ton fichier MK_Suite.exe se trouve dans :
echo   %cd%\dist\MK_Suite.exe
echo.
echo   Tu peux le copier sur ton Bureau ou une cle USB.
echo ============================================
pause
