@echo off
chcp 65001 >nul
title Compilar o Espelho
cd /d "%~dp0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" goto semcompilador
if not exist "Espelho.cs" goto semcodigo

echo Compilando o Espelho...
"%CSC%" /nologo /target:winexe /optimize+ /codepage:65001 /out:Espelho.exe /win32icon:espelho.ico /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll Espelho.cs
if errorlevel 1 goto erro

echo.
echo Pronto! O arquivo Espelho.exe foi criado nesta pasta.
echo.
if not exist "Assinar.bat" goto fim
choice /c SN /n /m "Quer assinar o programa digitalmente agora? [S/N] "
if errorlevel 2 goto fim
call "%~dp0Assinar.bat"
exit /b 0

:fim
pause
exit /b 0

:semcompilador
echo Não encontrei o compilador do .NET Framework 4 neste computador.
echo Ele vem junto com o Windows 10 e o Windows 11. Se faltar, ative o
echo ".NET Framework 4.8" em Painel de Controle ^> Programas ^> Ativar ou desativar recursos do Windows.
pause
exit /b 1

:semcodigo
echo Não encontrei o arquivo Espelho.cs nesta pasta.
echo Deixe o Compilar.bat, o Espelho.cs e o espelho.ico juntos.
pause
exit /b 1

:erro
echo.
echo Deu erro ao compilar. Tire uma foto desta tela e me envie.
pause
exit /b 1
