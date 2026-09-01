@echo off
REM @author Florent HAZARD <f.hazard@sowapps.com>
REM Lanceur robuste du panneau Vigie.
REM Ignore la strategie d'execution et le marquage "fichier telecharge".
REM Double-clic OK ; demande l'elevation (UAC) automatiquement via run.ps1.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
if errorlevel 1 pause
