@echo off
REM @author Florent HAZARD <f.hazard@sowapps.com>
REM ---------------------------------------------------------------------------
REM uninstall.cmd - Remove Vigie from this computer. Double-click, and that is all.
REM
REM Same shape as setup.cmd, and for the same reasons: a .cmd file is read in the OEM
REM code page, so the code page switches to 65001 on the very first line -- and the
REM accents stay, because they are not negotiable (D41).
REM
REM WHAT IS ANNOUNCED BEFORE THE ELEVATION. Uninstalling deletes the Vigie data of ALL
REM accounts on this computer. Nobody expects that, so the window says it and offers
REM to quit, BEFORE Windows asks for the rights.
REM
REM Target: doc/progress/targeting/uninstall.md
REM ---------------------------------------------------------------------------
@chcp 65001 >nul
setlocal
title Désinstallation de Vigie
mode con: cols=120 lines=45 >nul 2>&1

REM WINDOWS TOOLS ARE CALLED BY THEIR FULL PATH: whoami and find also exist in Git Bash
REM and MSYS, and the PATH then decides who answers (measured on 31/08).
"%SystemRoot%\System32\whoami.exe" /groups | "%SystemRoot%\System32\find.exe" "S-1-5-32-544" >nul 2>&1
if errorlevel 1 goto :pasadmin

"%SystemRoot%\System32\net.exe" session >nul 2>&1
if not errorlevel 1 goto :desinstalle

echo.
echo La désinstallation de Vigie demande des droits supplémentaires.
echo Une fenêtre va expliquer ce qui sera supprimé, avant toute modification.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\lib\show-confirm.ps1" -Scenario desinstallation
if errorlevel 1 goto :refus

echo Une fenêtre de confirmation Windows va s'ouvrir.
set "VIGIE_SELF=%~f0"
powershell -NoProfile -Command "Start-Process -FilePath $env:VIGIE_SELF -Verb RunAs"
exit /b

:refus
echo.
echo Désinstallation annulée. Rien n'a été modifié sur cet ordinateur.
echo.
pause
exit /b 3

:desinstalle
REM POWERSHELL 7 WHEN IT IS THERE. The project targets pwsh (D41): the installation switches
REM to it by itself, and the uninstall must read the same library the same way. Windows
REM PowerShell stays the fallback -- one uninstalls precisely on the day things are broken,
REM and pwsh may already be gone.
set "VIGIE_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%VIGIE_PWSH%" goto :avecpwsh
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\uninstall.ps1" -Yes
if errorlevel 1 goto :partiel
exit /b 0

:avecpwsh
"%VIGIE_PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\uninstall.ps1" -Yes
if errorlevel 1 goto :partiel
exit /b 0

:pasadmin
echo.
echo Ce compte Windows n'est pas administrateur.
echo La désinstallation retire une tâche de démarrage, un compte local et un
echo dossier de Program Files : elle demande les mêmes droits que l'installation.
echo.
echo Ouvrez une session administrateur, puis relancez ce fichier.
echo.
pause
exit /b 1

:partiel
REM THE PAUSE STAYS HERE, AND ONLY HERE. This is the one case where the screen carries a
REM list to read -- what could not be removed, and how to do it by hand.
echo.
echo La désinstallation est INCOMPLÈTE. La liste ci-dessus dit ce qui reste.
echo.
pause
exit /b 1
