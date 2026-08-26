@echo off
REM ---------------------------------------------------------------------------
REM setup.cmd - LE point d entree de Vigie. Double-clic, et c est tout.
REM
REM Il fait la totalite : PowerShell 7 pour la machine, le module Pode, le jeton
REM local, la tache de demarrage de CE compte, et le lancement de l application.
REM
REM Le compte courant doit etre ADMINISTRATEUR : Vigie tient le verrou de Windows
REM Update et installe pour toute la machine. On le verifie AVANT d elever -- sans
REM ce controle, Windows demanderait les identifiants d un AUTRE compte et Vigie
REM s installerait pour celui-la, pas pour vous.
REM
REM La premiere passe se fait avec Windows PowerShell, present partout : quand on
REM installe, pwsh n existe pas forcement encore. install.ps1 bascule tout seul.
REM ---------------------------------------------------------------------------
setlocal
title Installation de Vigie

whoami /groups | find "S-1-5-32-544" >nul 2>&1
if errorlevel 1 goto :pasadmin

net session >nul 2>&1
if not errorlevel 1 goto :installe
echo Vigie a besoin des droits administrateur.
echo Une fenetre de confirmation Windows va s ouvrir.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:installe
echo.
echo === Installation de Vigie ===
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1"
REM LE RESULTAT SE LIT : annoncer « Termine » apres un echec est pire que se taire.
if errorlevel 1 goto :echec
echo.
echo Vigie est installee et lancee.
echo Panneau : http://127.0.0.1:47600/
echo Elle reviendra a chaque ouverture de session.
echo.
pause
exit /b 0

:pasadmin
echo.
echo Ce compte Windows n est pas administrateur.
echo Vigie s installe pour le compte qui lance ce setup, et ce compte doit etre
echo administrateur : elle tient le verrou de Windows Update et installe
echo PowerShell 7 pour toute la machine.
echo.
echo Ouvrez une session administrateur, puis relancez ce fichier.
echo.
pause
exit /b 1

:echec
echo.
echo L installation a ECHOUE. Les lignes ci-dessus nomment la cause.
echo Journal detaille : apps\backend-pode\var\log\install_*.log
echo.
pause
exit /b 1
