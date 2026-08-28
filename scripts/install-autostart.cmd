@echo off
REM Installe l'app barre systeme au demarrage de session (demande UAC).
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-autostart.ps1"
if errorlevel 1 pause
