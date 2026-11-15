@echo off
chcp 65001 >nul
title Confiar no Espelho
cd /d "%~dp0"
if not exist "Espelho.cer" (
  echo Não encontrei o arquivo Espelho.cer nesta pasta.
  pause
  exit /b 1
)
echo O Windows vai perguntar se você quer instalar o certificado do Espelho.
echo Clique em SIM. Isso é feito só uma vez neste computador.
echo.
certutil -user -addstore TrustedPublisher "Espelho.cer" >nul
certutil -user -addstore Root "Espelho.cer" >nul
echo.
echo Pronto! Agora o Windows confia no Espelho.exe assinado por este certificado.
pause
