@echo off
chcp 65001 >nul
title Assinar o Espelho
set "ASS_FILE=%~f0"
set "ASS_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:ASS_FILE,[Text.Encoding]::UTF8); $i=$t.IndexOf('#PS'+'START'); Invoke-Expression $t.Substring($i)"
echo.
pause
exit /b
#PSSTART
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
try {
  $dir = $env:ASS_DIR.TrimEnd('\')
  $exe = Join-Path $dir 'Espelho.exe'
  $cer = Join-Path $dir 'Espelho.cer'
  if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host 'Não encontrei o Espelho.exe. Dê dois cliques no Compilar.bat primeiro.' -ForegroundColor Yellow
    return
  }

  # 1) certificado próprio (criado só na primeira vez)
  $subject = 'CN=Espelhô (assinatura própria)'
  $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
          Where-Object { $_.Subject -eq $subject -and $_.NotAfter -gt (Get-Date).AddDays(30) } |
          Select-Object -First 1
  if (-not $cert) {
    Write-Host 'Criando o certificado de assinatura (só na primeira vez)...'
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $subject -KeyUsage DigitalSignature `
            -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 `
            -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(5)
  }
  [void](Export-Certificate -Cert $cert -FilePath $cer -Force)

  # 2) confiar nesse certificado neste computador
  Write-Host ''
  Write-Host 'O Windows vai perguntar se você quer instalar o certificado. Clique em SIM.' -ForegroundColor Cyan
  foreach ($store in 'TrustedPublisher', 'Root') {
    try { [void](Import-Certificate -FilePath $cer -CertStoreLocation "Cert:\CurrentUser\$store") }
    catch { Write-Host "Não consegui confiar no certificado em $store (você recusou?)." -ForegroundColor Yellow }
  }

  # 3) assinar o programa
  Write-Host 'Assinando o Espelho.exe...'
  try { [void](Set-AuthenticodeSignature -FilePath $exe -Certificate $cert -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com') } catch {}
  $sig = Get-AuthenticodeSignature -LiteralPath $exe
  if (-not $sig.SignerCertificate) {
    # sem internet: assina sem carimbo de data
    [void](Set-AuthenticodeSignature -FilePath $exe -Certificate $cert -HashAlgorithm SHA256)
    $sig = Get-AuthenticodeSignature -LiteralPath $exe
  }

  Write-Host ''
  if ($sig.SignerCertificate -and $sig.Status -eq 'Valid') {
    Write-Host 'Pronto! O Espelho.exe está assinado e a assinatura é válida neste computador.' -ForegroundColor Green
  } elseif ($sig.SignerCertificate) {
    Write-Host 'O Espelho.exe foi assinado, mas este computador ainda não confia no certificado.' -ForegroundColor Yellow
    Write-Host 'Rode o Assinar.bat de novo e clique em SIM quando o Windows perguntar.'
  } else {
    Write-Host 'Não consegui assinar o Espelho.exe.' -ForegroundColor Red
  }
  Write-Host ''
  Write-Host 'Para outro computador (ex.: o da sua namorada), leve o Espelho.exe, o Espelho.cer'
  Write-Host 'e o ConfiarNoCertificado.bat, e rode o ConfiarNoCertificado.bat nele uma vez.'
} catch {
  Write-Host ('Erro: ' + $_.Exception.Message) -ForegroundColor Red
}
