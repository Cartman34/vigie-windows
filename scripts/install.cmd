@echo off
REM ---------------------------------------------------------------------------
REM install.cmd - Installe Vigie et ses dependances. DOUBLE-CLIC.
REM
REM Pourquoi ce fichier existe : l installation touche a PowerShell 7 pour TOUTE
REM la machine, ce qui exige l elevation. Sans elle, winget retire l eventuelle
REM version du compte puis echoue -- et la machine se retrouve sans PowerShell
REM du tout (vecu le 26/08). Ce lanceur demande donc l elevation lui-meme.
REM
REM Il n utilise PAS pwsh : quand on installe, il n existe pas encore. C est
REM Windows PowerShell (present partout) qui fait la premiere passe.
REM ---------------------------------------------------------------------------
setlocal
title Installation de Vigie

REM --- Elevation : on la demande au lieu d echouer plus loin ---
net session >nul 2>&1
if not errorlevel 1 goto :installe
echo Cette installation demande les droits administrateur.
echo Une fenetre de confirmation Windows va s ouvrir.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:installe
echo.
echo === Vigie : installation des prerequis ===
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"

REM --- Seconde passe : PowerShell 7 vient d etre installe, on finit avec lui.
REM     Le chemin est celui de l installation MACHINE ; le PATH de cette fenetre,
REM     lui, date d avant l installation et ne connait pas encore pwsh.
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%PWSH%" goto :fin
echo.
echo === Seconde passe avec PowerShell 7 ===
echo.
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"

:fin
echo.
echo Termine. Pour lancer Vigie : double-clic sur run.cmd
echo.
pause
