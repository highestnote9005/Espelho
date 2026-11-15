@echo off
set "JOGAR_FILE=%~f0"
set "JOGAR_DIR=%~dp0"
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$t=[IO.File]::ReadAllText($env:JOGAR_FILE,[Text.Encoding]::UTF8); $i=$t.IndexOf('#PS'+'START'); Invoke-Expression $t.Substring($i)"
exit /b
#PSSTART
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
  Add-Type -Namespace Win -Name Dpi -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
  [Win.Dpi]::SetProcessDPIAware() | Out-Null
} catch {}
[Windows.Forms.Application]::EnableVisualStyles()
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

try {

# ---------------------------------------------------------------- caminhos
if ($env:JOGAR_DIR) { $Base = $env:JOGAR_DIR.TrimEnd('\') } else { $Base = (Get-Location).Path }
$Prog    = Join-Path $Base 'programa'
$Scrcpy  = Join-Path $Prog 'scrcpy.exe'
$Adb     = Join-Path $Prog 'adb.exe'
$CfgFile = Join-Path $Base 'configuracoes.json'
$IcoFile = Join-Path $Base 'espelho.ico'

# ---------------------------------------------------------------- cores
function Col($hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
$cBg     = Col '#12141C'
$cCard   = Col '#1C2030'
$cLine   = Col '#2B3048'
$cText   = Col '#F2F4FA'
$cMuted  = Col '#9AA3BC'
$cAccent = Col '#7C5CFF'
$cField  = Col '#262B40'

# ---------------------------------------------------------------- estado
$St = @{ state = 'init'; color = $cAccent; key = ''; busy = $false; progress = -1.0
         serial = $null; name = ''; wireless = $false; proc = $null; out = $null; err = $null; t0 = (Get-Date)
         pend = $null; appsPend = $null; appsFor = $null; appsLoaded = $false; appPkgs = @($null)
         hover = $false; startapp = $false; gamepad = $false
         rec = $false; recFile = $null; flashBtn = $null; flashOld = '' }

# ---------------------------------------------------------------- configuracoes salvas
$Settings = @{ quality = 1; fullscreen = $false; audio = $true; screenoff = $false; touch = $true
               pad = $false; showtouches = $false; app = '' }
try {
  if (Test-Path -LiteralPath $CfgFile) {
    $j = Get-Content -LiteralPath $CfgFile -Raw | ConvertFrom-Json
    foreach ($k in @($Settings.Keys)) { if ($j.PSObject.Properties[$k]) { $Settings[$k] = $j.$k } }
  }
} catch {}

$Quality = [ordered]@{
  'Leve (computador mais fraco)' = '-m 960 -b 4M'
  'Equilibrada (recomendada)'    = '-m 1280 -b 8M'
  'Máxima (mais nítida)'         = '-b 16M'
}

# ---------------------------------------------------------------- utilidades de desenho
function RoundRect($r, $rad) {
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  $d = $rad * 2
  $p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
  $p.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
  $p.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
  $p.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}
function Ln($g, $pen, $x1, $y1, $x2, $y2) {
  $g.DrawLine($pen, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
}
function DB($c) {
  $c.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($c, $true, $null)
}
function New-Lbl($text, $x, $y, $w, $h, $size, $bold, $color, $back) {
  $l = New-Object Windows.Forms.Label
  $l.AutoSize = $false
  $l.Text = $text
  $l.Location = [Drawing.Point]::new($x, $y)
  $l.Size = [Drawing.Size]::new($w, $h)
  if ($bold) { $style = [Drawing.FontStyle]::Bold } else { $style = [Drawing.FontStyle]::Regular }
  $l.Font = [Drawing.Font]::new('Segoe UI', [single]$size, $style)
  $l.ForeColor = $color
  $l.BackColor = $back
  return $l
}
function Msg($text, $icon = 'Information') {
  [Windows.Forms.MessageBox]::Show($form, $text, 'Espelhô', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]$icon) | Out-Null
}

# ---------------------------------------------------------------- icone proprio do programa
function New-AppBitmap([int]$size) {
  $bmp = New-Object Drawing.Bitmap($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
  $rect = [Drawing.Rectangle]::new(0, 0, $size, $size)
  $br = [Drawing.Drawing2D.LinearGradientBrush]::new($rect, (Col '#7C5CFF'), (Col '#3B82F6'), 45.0)
  $g.FillPath($br, (RoundRect ([Drawing.Rectangle]::new(0, 0, $size - 1, $size - 1)) ([int]($size * 0.22))))
  $pw = [int]($size * 0.40); $ph = [int]($size * 0.68)
  $px = [int](($size - $pw) / 2); $py = [int](($size - $ph) / 2)
  $pen = [Drawing.Pen]::new([Drawing.Color]::White, [single]([Math]::Max(1.5, $size * 0.045)))
  $g.DrawPath($pen, (RoundRect ([Drawing.Rectangle]::new($px, $py, $pw, $ph)) ([int]([Math]::Max(1, $size * 0.07)))))
  # reflexo de espelho dentro da tela do celular
  $g.SetClip((RoundRect ([Drawing.Rectangle]::new($px, $py, $pw, $ph)) ([int]([Math]::Max(1, $size * 0.07)))))
  $glare = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(120, 255, 255, 255))
  $mk = { param($x, $y) [Drawing.PointF]::new([single]$x, [single]$y) }
  $d = $pw * 0.90
  $a = $px + $pw * 0.55; $wd = $pw * 0.30
  $g.FillPolygon($glare, [Drawing.PointF[]]@((& $mk $a $py), (& $mk ($a + $wd) $py), (& $mk ($a + $wd - $d) ($py + $ph)), (& $mk ($a - $d) ($py + $ph))))
  $a = $px + $pw * 0.98; $wd = $pw * 0.10
  $g.FillPolygon($glare, [Drawing.PointF[]]@((& $mk $a $py), (& $mk ($a + $wd) $py), (& $mk ($a + $wd - $d) ($py + $ph)), (& $mk ($a - $d) ($py + $ph))))
  $g.ResetClip()
  $g.Dispose()
  return $bmp
}
function Save-Icon($path) {
  $sizes = @(256, 48, 32, 16); $pngs = @()
  foreach ($sz in $sizes) {
    $b = New-AppBitmap $sz
    $ms = New-Object IO.MemoryStream
    $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $pngs += , ($ms.ToArray())
    $b.Dispose()
  }
  $fs = [IO.File]::Create($path)
  $w = New-Object IO.BinaryWriter($fs)
  $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
  $offset = 6 + 16 * $sizes.Count
  for ($i = 0; $i -lt $sizes.Count; $i++) {
    $sz = $sizes[$i]; if ($sz -ge 256) { $dim = 0 } else { $dim = $sz }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
    $offset += $pngs[$i].Length
  }
  foreach ($d in $pngs) { $w.Write([byte[]]$d) }
  $w.Close(); $fs.Close()
}

# ---------------------------------------------------------------- manipuladores de desenho
$PaintCard = {
  param($sender, $e)
  $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
  $path = RoundRect ([Drawing.Rectangle]::new(0, 0, $sender.Width - 1, $sender.Height - 1)) 16
  $g.FillPath([Drawing.SolidBrush]::new($cCard), $path)
  $g.DrawPath([Drawing.Pen]::new($cLine, 1.0), $path)
}
$RoundRegion = {
  param($sender, $e)
  $sender.Region = [Drawing.Region]::new((RoundRect ([Drawing.Rectangle]::new(0, 0, $sender.Width, $sender.Height)) 12))
}
$BadgePaint = {
  param($sender, $e)
  $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
  $g.FillEllipse([Drawing.SolidBrush]::new($cAccent), 0, 0, $sender.Width - 1, $sender.Height - 1)
  $fmt = New-Object Drawing.StringFormat
  $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $f = [Drawing.Font]::new('Segoe UI', [single]11, [Drawing.FontStyle]::Bold)
  $rect = [Drawing.RectangleF]::new(0, 0, $sender.Width, $sender.Height)
  $g.DrawString([string]$sender.Tag, $f, [Drawing.Brushes]::White, $rect, $fmt)
}
$IconPaint = {
  param($sender, $e)
  $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
  $w = $sender.Width; $h = $sender.Height; $col = $St.color
  $pw = [int]($w * 0.52); $ph = [int]($h * 0.94)
  $rx = [int](($w - $pw) / 2); $ry = [int](($h - $ph) / 2)
  $pen = [Drawing.Pen]::new($col, 3.0)
  $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
  $g.DrawPath($pen, (RoundRect ([Drawing.Rectangle]::new($rx, $ry, $pw, $ph)) 10))
  $cx = $w / 2.0; $cy = $h / 2.0
  Ln $g $pen ($cx - 6) ($ry + 8) ($cx + 6) ($ry + 8)
  $pen4 = [Drawing.Pen]::new($col, 4.0)
  $pen4.StartCap = 'Round'; $pen4.EndCap = 'Round'; $pen4.LineJoin = 'Round'
  $brush = [Drawing.SolidBrush]::new($col)
  switch ($St.state) {
    'ready' {
      Ln $g $pen4 ($cx - 9) ($cy + 2) ($cx - 2) ($cy + 9)
      Ln $g $pen4 ($cx - 2) ($cy + 9) ($cx + 10) ($cy - 7)
    }
    'play' {
      $pts = [Drawing.PointF[]]@(
        [Drawing.PointF]::new([single]($cx - 6), [single]($cy - 11)),
        [Drawing.PointF]::new([single]($cx - 6), [single]($cy + 11)),
        [Drawing.PointF]::new([single]($cx + 10), [single]$cy))
      $g.FillPolygon($brush, $pts)
    }
    { $_ -in 'allow', 'error' } {
      Ln $g $pen4 $cx ($cy - 12) $cx ($cy + 3)
      $g.FillEllipse($brush, [single]($cx - 3), [single]($cy + 9), 6.0, 6.0)
    }
    'download' {
      Ln $g $pen4 $cx ($cy - 11) $cx ($cy + 8)
      Ln $g $pen4 ($cx - 8) ($cy + 1) $cx ($cy + 9)
      Ln $g $pen4 ($cx + 8) ($cy + 1) $cx ($cy + 9)
    }
    default {
      foreach ($dx in -12, -3, 6) { $g.FillEllipse($brush, [single]($cx + $dx), [single]($cy - 3), 6.0, 6.0) }
    }
  }
}
$BarPaint = {
  param($sender, $e)
  $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
  $w = $sender.Width - 1; $h = $sender.Height - 1
  $g.FillPath([Drawing.SolidBrush]::new($cLine), (RoundRect ([Drawing.Rectangle]::new(0, 0, $w, $h)) 4))
  if ($St.progress -gt 0) {
    $fw = [int]([Math]::Max(8, $w * [Math]::Min(1.0, $St.progress)))
    $g.FillPath([Drawing.SolidBrush]::new($cAccent), (RoundRect ([Drawing.Rectangle]::new(0, 0, $fw, $h)) 4))
  }
}

# ---------------------------------------------------------------- janela principal
$form = New-Object Windows.Forms.Form
$form.Text = 'Espelhô'
$form.AutoScaleDimensions = [Drawing.SizeF]::new(96, 96)
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = [Drawing.Size]::new(460, 646)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $cBg
$form.ForeColor = $cText
$form.Font = [Drawing.Font]::new('Segoe UI', [single]10)
try { $form.Icon = [Drawing.Icon]::FromHandle((New-AppBitmap 32).GetHicon()) } catch {}

$tt = New-Object Windows.Forms.ToolTip
$tt.InitialDelay = 400; $tt.AutoPopDelay = 9000

$accentBar = New-Object Windows.Forms.Panel
$accentBar.Dock = 'Top'; $accentBar.Height = 5; $accentBar.BackColor = $cAccent

$lblHead = New-Lbl 'Espelhô' 24 12 412 40 20 $true $cText $cBg
$lblSub  = New-Lbl 'Seu celular na tela do PC. Conecte, escolha o jogo e jogue.' 26 52 412 22 10 $false $cMuted $cBg

# cartão de status
$cardStatus = New-Object Windows.Forms.Panel
$cardStatus.Location = [Drawing.Point]::new(20, 84); $cardStatus.Size = [Drawing.Size]::new(420, 128)
$cardStatus.BackColor = $cBg; DB $cardStatus
$cardStatus.Add_Paint($PaintCard)

$icon = New-Object Windows.Forms.Panel
$icon.Location = [Drawing.Point]::new(20, 14); $icon.Size = [Drawing.Size]::new(70, 92)
$icon.BackColor = $cCard; DB $icon
$icon.Add_Paint($IconPaint)

$lblTitle = New-Lbl '' 108 18 296 30 14 $true $cText $cCard
$lblDesc  = New-Lbl '' 108 52 298 62 9.5 $false $cMuted $cCard

$bar = New-Object Windows.Forms.Panel
$bar.Location = [Drawing.Point]::new(20, 112); $bar.Size = [Drawing.Size]::new(380, 8)
$bar.BackColor = $cCard; $bar.Visible = $false; DB $bar
$bar.Add_Paint($BarPaint)
$cardStatus.Controls.AddRange(@($icon, $lblTitle, $lblDesc, $bar))

# escolha do jogo
$lblGame = New-Lbl 'Jogo para abrir sozinho' 24 220 300 20 9 $false $cMuted $cBg
$cmbApp = New-Object Windows.Forms.ComboBox
$cmbApp.DropDownStyle = 'DropDownList'; $cmbApp.FlatStyle = 'Flat'
$cmbApp.BackColor = $cField; $cmbApp.ForeColor = $cText
$cmbApp.Location = [Drawing.Point]::new(20, 242); $cmbApp.Size = [Drawing.Size]::new(376, 28)
$cmbApp.MaxDropDownItems = 12
[void]$cmbApp.Items.Add('Não abrir nada (eu abro no celular)')
$cmbApp.SelectedIndex = 0
$btnRefApps = New-Object Windows.Forms.Button
$btnRefApps.Text = '↻'; $btnRefApps.Location = [Drawing.Point]::new(404, 241); $btnRefApps.Size = [Drawing.Size]::new(36, 30)
$btnRefApps.FlatStyle = 'Flat'; $btnRefApps.FlatAppearance.BorderSize = 0
$btnRefApps.BackColor = $cField; $btnRefApps.ForeColor = $cText; $btnRefApps.UseVisualStyleBackColor = $false
$btnRefApps.Font = [Drawing.Font]::new('Segoe UI', [single]12, [Drawing.FontStyle]::Bold); $btnRefApps.Cursor = 'Hand'
$btnRefApps.FlatAppearance.MouseOverBackColor = $cLine

# botão jogar
$btnPlay = New-Object Windows.Forms.Button
$btnPlay.Location = [Drawing.Point]::new(20, 286); $btnPlay.Size = [Drawing.Size]::new(420, 60)
$btnPlay.FlatStyle = 'Flat'; $btnPlay.FlatAppearance.BorderSize = 0
$btnPlay.Font = [Drawing.Font]::new('Segoe UI', [single]15, [Drawing.FontStyle]::Bold)
$btnPlay.UseVisualStyleBackColor = $false
$btnPlay.Add_SizeChanged($RoundRegion)

# botões pequenos
function New-SecBtn($text, $x, $y) {
  $b = New-Object Windows.Forms.Button
  $b.Text = $text; $b.Location = [Drawing.Point]::new($x, $y); $b.Size = [Drawing.Size]::new(136, 38)
  $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
  $b.BackColor = $cCard; $b.ForeColor = $cText; $b.UseVisualStyleBackColor = $false
  $b.Font = [Drawing.Font]::new('Segoe UI', [single]9.5)
  $b.FlatAppearance.MouseOverBackColor = $cField; $b.FlatAppearance.MouseDownBackColor = $cLine
  $b.Cursor = 'Hand'
  $b.Add_SizeChanged($RoundRegion)
  return $b
}
$btnRec    = New-SecBtn '●  Gravar' 20 358
$btnShot   = New-SecBtn 'Capturar tela' 162 358
$btnFolder = New-SecBtn 'Abrir pasta Jogos' 304 358

# cartão de configurações
$cardCfg = New-Object Windows.Forms.Panel
$cardCfg.Location = [Drawing.Point]::new(20, 408); $cardCfg.Size = [Drawing.Size]::new(420, 176)
$cardCfg.BackColor = $cBg; DB $cardCfg
$cardCfg.Add_Paint($PaintCard)

$lblCfg = New-Lbl 'Configurações' 20 12 300 26 12 $true $cText $cCard
$lblQ   = New-Lbl 'Qualidade' 20 48 100 24 10 $false $cMuted $cCard

$cmbQ = New-Object Windows.Forms.ComboBox
$cmbQ.DropDownStyle = 'DropDownList'; $cmbQ.FlatStyle = 'Flat'
$cmbQ.BackColor = $cField; $cmbQ.ForeColor = $cText
$cmbQ.Location = [Drawing.Point]::new(120, 44); $cmbQ.Size = [Drawing.Size]::new(280, 28)
foreach ($k in $Quality.Keys) { [void]$cmbQ.Items.Add($k) }
$qi = 1; try { $qi = [int]$Settings.quality } catch {}
if ($qi -lt 0 -or $qi -ge $cmbQ.Items.Count) { $qi = 1 }
$cmbQ.SelectedIndex = $qi

function New-Chk($text, $x, $y, $w, $checked) {
  $c = New-Object Windows.Forms.CheckBox
  $c.Text = $text; $c.Checked = [bool]$checked
  $c.Location = [Drawing.Point]::new($x, $y); $c.Size = [Drawing.Size]::new($w, 26)
  $c.BackColor = $cCard; $c.ForeColor = $cText; $c.FlatStyle = 'Standard'
  return $c
}
$chkFull  = New-Chk 'Tela cheia' 20 84 196 $Settings.fullscreen
$chkOff   = New-Chk 'Apagar tela do celular' 20 112 196 $Settings.screenoff
$chkPad   = New-Chk 'Usar controle' 20 140 196 $Settings.pad
$chkAudio = New-Chk 'Som no computador' 222 84 190 $Settings.audio
$chkTouch = New-Chk 'Toque mais preciso' 222 112 190 $Settings.touch
$chkShow  = New-Chk 'Mostrar toques' 222 140 190 $Settings.showtouches
$cardCfg.Controls.AddRange(@($lblCfg, $lblQ, $cmbQ, $chkFull, $chkOff, $chkPad, $chkAudio, $chkTouch, $chkShow))

$btnWifi  = New-SecBtn 'Sem cabo (Wi-Fi)' 20 598
$btnShort = New-SecBtn 'Criar atalho' 162 598
$btnHelp  = New-SecBtn 'Ajuda' 304 598

$form.Controls.AddRange(@($accentBar, $lblHead, $lblSub, $cardStatus, $lblGame, $cmbApp, $btnRefApps, $btnPlay,
                          $btnRec, $btnShot, $btnFolder, $cardCfg, $btnWifi, $btnShort, $btnHelp))

$tt.SetToolTip($cmbApp, 'Escolha o jogo: ele abre sozinho no celular quando você clica em JOGAR.')
$tt.SetToolTip($btnRefApps, 'Atualizar a lista de jogos do celular')
$tt.SetToolTip($btnRec, 'Liga a gravação. Ela começa ao clicar em JOGAR e termina ao fechar a janela do jogo. Se clicar durante o jogo, a imagem pisca por um instante.')
$tt.SetToolTip($btnShot, 'Tira uma foto da tela do celular e salva na pasta Jogos da Área de Trabalho.')
$tt.SetToolTip($btnFolder, 'Abre a pasta Jogos, onde ficam as gravações e capturas.')
$tt.SetToolTip($chkOff, 'Deixe desmarcado se alguém for tocar na tela do celular.')
$tt.SetToolTip($chkPad, 'Ligue o controle no PC (USB ou Bluetooth) antes de jogar. O jogo precisa aceitar controle.')
$tt.SetToolTip($chkTouch, 'Evita que o simples movimento do mouse atrapalhe os toques.')
$tt.SetToolTip($chkShow, 'Mostra um ponto na tela onde alguém toca. Ajuda quem está só assistindo.')
$tt.SetToolTip($btnWifi, 'Conecta por Wi-Fi para você poder tirar o cabo USB.')
$tt.SetToolTip($btnShort, 'Cria um atalho com ícone na Área de Trabalho.')

# ---------------------------------------------------------------- visual de acordo com o estado
function Update-Button {
  switch ($St.state) {
    'ready' {
      $btnPlay.Text = '▶   JOGAR'; $btnPlay.BackColor = Col '#22C55E'; $btnPlay.ForeColor = Col '#08210F'
      $btnPlay.FlatAppearance.MouseOverBackColor = Col '#34D874'; $btnPlay.FlatAppearance.MouseDownBackColor = Col '#16A34A'
      $btnPlay.Cursor = 'Hand'
    }
    'play' {
      $btnPlay.Text = 'Jogando…'; $btnPlay.BackColor = $cAccent; $btnPlay.ForeColor = [Drawing.Color]::White
      $btnPlay.FlatAppearance.MouseOverBackColor = $cAccent; $btnPlay.FlatAppearance.MouseDownBackColor = $cAccent
      $btnPlay.Cursor = 'Default'
    }
    'error' {
      $btnPlay.Text = 'Tentar de novo'; $btnPlay.BackColor = $cAccent; $btnPlay.ForeColor = [Drawing.Color]::White
      $btnPlay.FlatAppearance.MouseOverBackColor = Col '#8F74FF'; $btnPlay.FlatAppearance.MouseDownBackColor = Col '#6A49F0'
      $btnPlay.Cursor = 'Hand'
    }
    default {
      $btnPlay.Text = 'Aguardando o celular…'; $btnPlay.BackColor = Col '#2B3048'; $btnPlay.ForeColor = $cMuted
      $btnPlay.FlatAppearance.MouseOverBackColor = Col '#2B3048'; $btnPlay.FlatAppearance.MouseDownBackColor = Col '#2B3048'
      $btnPlay.Cursor = 'Default'
    }
  }
}
function Update-Rec {
  if ($St.rec) {
    if ($St.state -eq 'play') { $btnRec.Text = '■  Parar gravação' } else { $btnRec.Text = '●  Gravar: ligado' }
    $btnRec.BackColor = Col '#DC2626'; $btnRec.ForeColor = [Drawing.Color]::White
    $btnRec.FlatAppearance.MouseOverBackColor = Col '#EF4444'; $btnRec.FlatAppearance.MouseDownBackColor = Col '#B91C1C'
  } else {
    $btnRec.Text = '●  Gravar'; $btnRec.BackColor = $cCard; $btnRec.ForeColor = $cText
    $btnRec.FlatAppearance.MouseOverBackColor = $cField; $btnRec.FlatAppearance.MouseDownBackColor = $cLine
  }
}
function Update-Secondary {
  $rdy = ($St.state -eq 'ready')
  $btnWifi.Enabled = ($rdy -and (-not $St.wireless))
  $btnRefApps.Enabled = ($rdy -and (-not $St.appsPend))
  $btnShot.Enabled = (($St.state -eq 'ready') -or ($St.state -eq 'play'))
}
function Set-State($name, $titleText, $desc, $hex) {
  $k = "$name|$titleText|$desc"
  if ($St.key -eq $k) { return }
  $St.key = $k; $St.state = $name; $St.color = Col $hex
  $lblTitle.Text = $titleText; $lblDesc.Text = $desc
  $icon.Invalidate(); Update-Button; Update-Rec; Update-Secondary
}
function Flash-Btn($btn, $text) {
  if ($St.flashBtn -and $St.flashBtn -ne $btn) { $St.flashBtn.Text = $St.flashOld }
  if (-not $flashTimer.Enabled) { $St.flashOld = $btn.Text }
  $St.flashBtn = $btn; $btn.Text = $text
  $flashTimer.Stop(); $flashTimer.Start()
}

# ---------------------------------------------------------------- adb
function Invoke-Adb([string]$argline) {
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Adb; $psi.Arguments = $argline
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $t = $p.StandardOutput.ReadToEndAsync(); $null = $p.StandardError.ReadToEndAsync()
    if (-not $t.Wait(6000)) { try { $p.Kill() } catch {}; return '' }
    return $t.Result
  } catch { return '' }
}
function Start-AdbServer {
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Adb; $psi.Arguments = 'start-server'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    [void]$p.WaitForExit(10000)
  } catch {}
}
function Get-Devices([string]$raw) {
  $res = @()
  foreach ($l in ($raw -split "`r?`n")) {
    if ($l -match '^(\S+)\s+(device|unauthorized|offline)\b') { $res += [pscustomobject]@{ Serial = $matches[1]; State = $matches[2] } }
  }
  return $res
}
# consulta assíncrona: não trava a janela enquanto o adb responde
function Begin-Poll {
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Adb; $psi.Arguments = 'devices'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $St.pend = @{ p = $p; t = $p.StandardOutput.ReadToEndAsync(); at = (Get-Date) }
    $null = $p.StandardError.ReadToEndAsync()
  } catch { $St.pend = $null }
}
# descobre o que esta versão do scrcpy sabe fazer
function Test-Features {
  $St.hover = $false; $St.startapp = $false; $St.gamepad = $false
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Scrcpy; $psi.Arguments = '--help'; $psi.WorkingDirectory = $Prog
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $t = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if ($t.Wait(6000) -and $e.Wait(2000)) {
      $help = $t.Result + $e.Result
      $St.hover    = [bool]($help -match 'no-mouse-hover')
      $St.startapp = [bool]($help -match 'start-app')
      $St.gamepad  = [bool]($help -match '--gamepad')
    } else { try { $p.Kill() } catch {} }
  } catch {}
  $chkPad.Enabled = $St.gamepad
  $chkTouch.Enabled = $St.hover
  if (-not $St.gamepad) { $tt.SetToolTip($chkPad, 'Esta versão do programa de espelhamento não aceita controle. Apague a pasta "programa" para baixar a versão mais nova.') }
}
function Get-PhoneName($serial) {
  $m = (Invoke-Adb "-s $serial shell getprop ro.product.model").Trim()
  $b = (Invoke-Adb "-s $serial shell getprop ro.product.manufacturer").Trim()
  if (-not $m) { return 'Seu celular' }
  if ($b -and ($m -notlike "$b*")) { $b = (Get-Culture).TextInfo.ToTitleCase($b.ToLower()); return "$b $m" }
  return $m
}
function Refresh-Phone { Apply-Devices (Invoke-Adb 'devices') }
function Apply-Devices([string]$raw) {
  $d = @(Get-Devices $raw)
  $ready  = @($d | Where-Object { $_.State -eq 'device' })
  $unauth = @($d | Where-Object { $_.State -eq 'unauthorized' })
  if ($ready.Count -gt 0) {
    $dev = $ready[0]
    $changed = ($St.serial -ne $dev.Serial)
    if ($changed) { $St.serial = $dev.Serial; $St.name = Get-PhoneName $dev.Serial }
    $St.wireless = ($dev.Serial -match ':')
    Set-State 'ready' 'Celular conectado' ("$($St.name) está pronto.`nEscolha o jogo e clique em JOGAR. Mantenha o celular desbloqueado.") '#22C55E'
    if ($changed -or ($St.appsFor -ne $St.serial)) { Begin-Apps }
  } elseif ($unauth.Count -gt 0) {
    $St.serial = $null; $St.wireless = $false
    Set-State 'allow' 'Falta uma permissão' "Olhe a tela do celular e toque em Permitir (marque Sempre permitir neste computador)." '#F59E0B'
  } else {
    $St.serial = $null; $St.wireless = $false
    Set-State 'nodevice' 'Conecte o celular' "Ligue o celular ao PC com o cabo USB e desbloqueie a tela.`nPrimeira vez? Clique em Ajuda." '#7C5CFF'
  }
  Update-Secondary
}

# ---------------------------------------------------------------- lista de jogos do celular
function Begin-Apps {
  if (-not $St.serial -or $St.appsPend) { return }
  if (-not (Test-Path -LiteralPath $Scrcpy)) { return }
  $St.appsFor = $St.serial
  $cmbApp.Items.Clear(); [void]$cmbApp.Items.Add('Carregando seus apps…'); $cmbApp.SelectedIndex = 0
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Scrcpy; $psi.Arguments = "-s $($St.serial) --list-apps"; $psi.WorkingDirectory = $Prog
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $St.appsPend = @{ p = $p; t = $p.StandardOutput.ReadToEndAsync(); e = $p.StandardError.ReadToEndAsync(); at = (Get-Date) }
  } catch { Apply-Apps '' }
  Update-Secondary
}
function Poll-Apps {
  if (-not $St.appsPend) { return }
  $ap = $St.appsPend
  if ($ap.t.IsCompleted -and $ap.e.IsCompleted) {
    $St.appsPend = $null
    Apply-Apps ($ap.t.Result + "`n" + $ap.e.Result)
  } elseif (((Get-Date) - $ap.at).TotalSeconds -gt 25) {
    try { $ap.p.Kill() } catch {}
    $St.appsPend = $null
    Apply-Apps ''
  }
}
function Apply-Apps([string]$raw) {
  $user = @(); $all = @()
  $pkgRx = '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'
  foreach ($l in ($raw -split "`r?`n")) {
    if ($l -match '^\s*(?:\[server\]\s+\w+:\s*)?([*-])\s+(\S.*)$') {
      $flag = $matches[1]; $rest = $matches[2].Trim()
      $tok = @($rest -split '\s+')
      $pkg = $null; $label = ''
      if ($tok[$tok.Count - 1] -match $pkgRx) {
        $pkg = $tok[$tok.Count - 1]
        if ($tok.Count -gt 1) { $label = ($tok[0..($tok.Count - 2)] -join ' ') }
      } elseif ($tok[0] -match $pkgRx) {
        $pkg = $tok[0]
        if ($tok.Count -gt 1) { $label = ($tok[1..($tok.Count - 1)] -join ' ') }
      }
      if ($pkg) {
        if (-not $label.Trim()) { $label = $pkg }
        $o = [pscustomobject]@{ Label = $label.Trim(); Pkg = $pkg }
        $all += $o
        if ($flag -eq '-') { $user += $o }
      }
    }
  }
  if ($user.Count -gt 0) { $list = $user } else { $list = $all }
  $list = @($list | Sort-Object Label)
  $cmbApp.Items.Clear(); $St.appPkgs = @($null)
  [void]$cmbApp.Items.Add('Não abrir nada (eu abro no celular)')
  foreach ($a in $list) { [void]$cmbApp.Items.Add($a.Label); $St.appPkgs += $a.Pkg }
  $idx = 0
  if ($Settings.app) {
    for ($i = 1; $i -lt $St.appPkgs.Count; $i++) { if ($St.appPkgs[$i] -eq $Settings.app) { $idx = $i; break } }
  }
  $cmbApp.SelectedIndex = $idx
  $St.appsLoaded = ($list.Count -gt 0)
  Update-Secondary
}

# ---------------------------------------------------------------- download automatico do programa
function Ensure-Program {
  if (Test-Path -LiteralPath $Scrcpy) { return $true }
  $St.busy = $true; $St.progress = 0.0; $bar.Visible = $true
  Set-State 'download' 'Preparando tudo' 'Baixando o necessário. Isso só acontece na primeira vez e precisa de internet.' '#7C5CFF'
  $ok = $false
  try {
    $url = $null
    try {
      $rel = Invoke-RestMethod 'https://api.github.com/repos/Genymobile/scrcpy/releases/latest' -UserAgent 'Espelho' -TimeoutSec 15
      $asset = $rel.assets | Where-Object { $_.name -like 'scrcpy-win64-*.zip' } | Select-Object -First 1
      if ($asset) { $url = $asset.browser_download_url }
    } catch {}
    if (-not $url) { $url = 'https://github.com/Genymobile/scrcpy/releases/download/v3.1/scrcpy-win64-v3.1.zip' }

    $zip = Join-Path $Base 'baixando.zip'
    $req = [Net.HttpWebRequest]::Create($url)
    $req.UserAgent = 'Espelho'; $req.Timeout = 30000; $req.ReadWriteTimeout = 30000
    $resp = $req.GetResponse(); $total = $resp.ContentLength
    $in = $resp.GetResponseStream(); $fs = [IO.File]::Create($zip)
    $buf = New-Object byte[] 65536; $done = 0; $lastPct = -1
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
      if ($form.IsDisposed) { break }
      $fs.Write($buf, 0, $n); $done += $n
      if ($total -gt 0) {
        $St.progress = [double]$done / $total
        $pct = [int]($St.progress * 100)
        if ($pct -ne $lastPct) { $lastPct = $pct; $bar.Invalidate(); $lblDesc.Text = "Baixando… $pct%`nSó acontece na primeira vez." }
      }
      [Windows.Forms.Application]::DoEvents()
    }
    $fs.Close(); $in.Close(); $resp.Close()
    if ($form.IsDisposed) { return $false }

    $lblDesc.Text = 'Instalando… quase lá.'; [Windows.Forms.Application]::DoEvents()
    $tmp = Join-Path $Base 'temp_extraido'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
    $dir = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    if (Test-Path -LiteralPath $Prog) { Remove-Item -LiteralPath $Prog -Recurse -Force }
    Move-Item -LiteralPath $dir.FullName -Destination $Prog
    Remove-Item -LiteralPath $tmp -Recurse -Force
    Remove-Item -LiteralPath $zip -Force
    $ok = (Test-Path -LiteralPath $Scrcpy)
  } catch { $ok = $false }
  if (-not $form.IsDisposed) {
    $St.busy = $false; $bar.Visible = $false; $St.progress = -1.0
    if (-not $ok) { Set-State 'error' 'Não consegui baixar' "Verifique a internet e clique em Tentar de novo." '#EF4444' }
  }
  return $ok
}
function Prepare {
  if (Ensure-Program) { Start-AdbServer; Test-Features; $St.key = ''; Refresh-Phone; $timer.Start() }
}

# ---------------------------------------------------------------- pasta Jogos, gravacao, captura
function Get-GamesDir {
  $desk = [Environment]::GetFolderPath('Desktop')
  if (-not $desk) { $desk = $Base }
  $d = Join-Path $desk 'Jogos'
  if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
  return $d
}
function Open-GamesFolder {
  try { Start-Process -FilePath (Get-GamesDir) } catch { Msg 'Não consegui abrir a pasta Jogos.' 'Warning' }
}
function Finish-Record {
  $f = $St.recFile; $St.recFile = $null
  if ($f -and (Test-Path -LiteralPath $f) -and ((Get-Item -LiteralPath $f).Length -gt 1000)) {
    $r = [Windows.Forms.MessageBox]::Show($form, "Gravação salva na pasta Jogos:`n$([IO.Path]::GetFileName($f))`n`nQuer abrir a pasta?", 'Espelhô', 'YesNo', 'Question')
    if ($r -eq 'Yes') { Open-GamesFolder }
  }
}
function Take-Shot {
  if (-not $St.serial) { Msg 'Conecte o celular primeiro.' 'Warning'; return }
  $file = Join-Path (Get-GamesDir) ("Print_{0:yyyy-MM-dd_HH-mm-ss}.png" -f (Get-Date))
  $form.Cursor = 'WaitCursor'; [Windows.Forms.Application]::DoEvents()
  $ok = $false; $fs = $null
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Adb; $psi.Arguments = "-s $($St.serial) exec-out screencap -p"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $fs = [IO.File]::Create($file)
    $c = $p.StandardOutput.BaseStream.CopyToAsync($fs)
    $null = $p.StandardError.ReadToEndAsync()
    if ($c.Wait(12000)) { $fs.Close(); $ok = ((Get-Item -LiteralPath $file).Length -gt 2000) }
    else { try { $p.Kill() } catch {}; $fs.Close() }
  } catch { try { if ($fs) { $fs.Close() } } catch {} }
  $form.Cursor = 'Default'
  if ($ok) { Flash-Btn $btnShot 'Salvo ✓' }
  else {
    try { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } } catch {}
    Msg "Não consegui tirar a foto da tela.`nAlguns apps bloqueiam capturas. Tente de novo." 'Warning'
  }
}

# ---------------------------------------------------------------- jogar
function Save-Settings {
  $Settings.quality = $cmbQ.SelectedIndex
  $Settings.fullscreen = $chkFull.Checked
  $Settings.audio = $chkAudio.Checked
  $Settings.screenoff = $chkOff.Checked
  $Settings.touch = $chkTouch.Checked
  $Settings.pad = $chkPad.Checked
  $Settings.showtouches = $chkShow.Checked
  if ($St.appsLoaded -and $St.appPkgs -and $cmbApp.SelectedIndex -ge 0 -and $cmbApp.SelectedIndex -lt $St.appPkgs.Count) {
    $Settings.app = [string]$St.appPkgs[$cmbApp.SelectedIndex]
  }
  try { $Settings | ConvertTo-Json | Set-Content -LiteralPath $CfgFile -Encoding UTF8 } catch {}
}
function Start-Game {
  if ($St.state -ne 'ready' -or -not $St.serial) { return }
  Save-Settings
  $q = $Quality[[string]$cmbQ.SelectedItem]
  $a = "-s $($St.serial) --window-title=`"Espelho`" --max-fps=60 --stay-awake $q"
  if ($chkFull.Checked)       { $a += ' -f' }
  if (-not $chkAudio.Checked) { $a += ' --no-audio' }
  if ($chkOff.Checked)        { $a += ' -S' }
  if ($chkTouch.Checked -and $St.hover) { $a += ' --no-mouse-hover' }
  if ($chkPad.Checked -and $St.gamepad) { $a += ' --gamepad=uhid' }
  if ($chkShow.Checked)       { $a += ' --show-touches' }
  $pkg = $null
  if ($St.startapp -and $St.appsLoaded -and $cmbApp.SelectedIndex -gt 0 -and $cmbApp.SelectedIndex -lt $St.appPkgs.Count) {
    $pkg = [string]$St.appPkgs[$cmbApp.SelectedIndex]
  }
  if ($pkg -and ($pkg -match '^[A-Za-z0-9_.]+$')) { $a += " --start-app=$pkg" }
  $St.recFile = $null
  if ($St.rec) {
    try {
      $St.recFile = Join-Path (Get-GamesDir) ("Partida_{0:yyyy-MM-dd_HH-mm-ss}.mp4" -f (Get-Date))
      $a += " --record=`"$($St.recFile)`""
    } catch { $St.recFile = $null }
  }
  try {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Scrcpy; $psi.Arguments = $a; $psi.WorkingDirectory = $Prog
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $St.proc = [Diagnostics.Process]::Start($psi)
    $St.out = $St.proc.StandardOutput.ReadToEndAsync(); $St.err = $St.proc.StandardError.ReadToEndAsync()
    $St.t0 = Get-Date
    $desc = "O jogo está aberto em outra janela.`nPara parar, é só fechar a janela do jogo."
    if ($St.recFile) { $desc = "Gravando a partida na pasta Jogos.`nPara parar, feche a janela do jogo." }
    Set-State 'play' 'Jogando!' $desc '#7C5CFF'
  } catch {
    $St.recFile = $null
    Msg "Não consegui abrir o jogo.`n$($_.Exception.Message)" 'Error'
  }
}
function Restart-Game {
  $p = $St.proc
  if (-not $p) { return }
  $form.Cursor = 'WaitCursor'; [Windows.Forms.Application]::DoEvents()
  try {
    [void]$p.CloseMainWindow()
    if (-not $p.WaitForExit(6000)) { $p.Kill(); [void]$p.WaitForExit(2000) }
  } catch {}
  $St.proc = $null; $St.key = ''
  Refresh-Phone
  Finish-Record
  Start-Game
  $form.Cursor = 'Default'
}
function Toggle-Rec {
  $St.rec = -not $St.rec
  Update-Rec
  if ($St.proc -and (-not $St.proc.HasExited)) { Restart-Game }
}
function Connect-Wifi {
  if ($St.state -ne 'ready' -or -not $St.serial -or $St.wireless) { return }
  $ser = $St.serial
  $form.Cursor = 'WaitCursor'; [Windows.Forms.Application]::DoEvents()
  $ip = $null
  $route = Invoke-Adb "-s $ser shell ip route"
  if ($route -match 'dev wlan0.*?src (\d+\.\d+\.\d+\.\d+)') { $ip = $matches[1] }
  if (-not $ip) {
    $form.Cursor = 'Default'
    Msg "Não achei o Wi-Fi do celular.`nLigue o Wi-Fi no celular, use a mesma rede do computador e tente de novo." 'Warning'
    return
  }
  [void](Invoke-Adb "-s $ser tcpip 5555")
  Start-Sleep -Seconds 2
  $r = Invoke-Adb "connect ${ip}:5555"
  $form.Cursor = 'Default'
  if ($r -match 'connected to') {
    Msg "Pronto! O celular está conectado por Wi-Fi.`nAgora você já pode tirar o cabo USB.`n`n(A imagem pode ter um pouco mais de atraso que no cabo.)"
    $St.key = ''; Refresh-Phone
  } else {
    Msg "Não deu certo conectar por Wi-Fi.`nConfira se o celular e o PC estão na mesma rede e tente de novo, ou continue usando o cabo." 'Warning'
  }
}
function New-Shortcut {
  try {
    if (-not $env:JOGAR_FILE) { Msg 'Abra o programa pelo arquivo Espelho.bat para criar o atalho.' 'Warning'; return }
    if (-not (Test-Path -LiteralPath $IcoFile)) { Save-Icon $IcoFile }
    $desk = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desk 'Espelhô.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = $env:JOGAR_FILE
    $s.WorkingDirectory = $Base
    $s.IconLocation = "$IcoFile,0"
    $s.WindowStyle = 7
    $s.Description = 'Espelhô – seu celular na tela do PC'
    $s.Save()
    Msg "Atalho criado na Área de Trabalho:`n""Espelhô""`n`nSe você mudar o arquivo Espelho.bat de pasta, crie o atalho de novo."
  } catch {
    Msg "Não consegui criar o atalho.`n$($_.Exception.Message)" 'Warning'
  }
}

# ---------------------------------------------------------------- ajuda
function Show-Help {
  $h = New-Object Windows.Forms.Form
  $h.Text = 'Como ativar a Depuração USB'
  $h.AutoScaleDimensions = [Drawing.SizeF]::new(96, 96); $h.AutoScaleMode = 'Dpi'
  $h.ClientSize = [Drawing.Size]::new(440, 560)
  $h.StartPosition = 'CenterParent'; $h.FormBorderStyle = 'FixedDialog'
  $h.MaximizeBox = $false; $h.MinimizeBox = $false; $h.ShowInTaskbar = $false
  $h.BackColor = $cBg; $h.ForeColor = $cText; $h.Font = [Drawing.Font]::new('Segoe UI', [single]10)
  $h.Controls.Add((New-Lbl 'Ativar a Depuração USB' 24 20 392 36 17 $true $cText $cBg))
  $h.Controls.Add((New-Lbl 'Você só precisa fazer isso uma vez, no celular Android.' 26 58 392 24 10 $false $cMuted $cBg))
  $steps = @(
    'Abra Configurações › Sobre o telefone.',
    'Toque 7 vezes em "Número da versão". Pode pedir sua senha ou PIN.',
    'Volte e abra "Opções do desenvolvedor" (fica em Sistema ou no fim da lista).',
    'Ative a chave "Depuração USB".',
    'Ligue o cabo USB no PC e toque em Permitir quando o celular perguntar.'
  )
  $y = 90; $i = 1
  foreach ($st2 in $steps) {
    $b = New-Object Windows.Forms.Panel
    $b.Location = [Drawing.Point]::new(24, $y); $b.Size = [Drawing.Size]::new(32, 32)
    $b.BackColor = $cBg; $b.Tag = "$i"; DB $b
    $b.Add_Paint($BadgePaint)
    $h.Controls.Add($b)
    $h.Controls.Add((New-Lbl $st2 72 ($y - 2) 350 52 10.5 $false $cText $cBg))
    $y += 62; $i++
  }
  $h.Controls.Add((New-Lbl 'Dicas: use um cabo que transfira dados (alguns só carregam). Em celulares Xiaomi, Redmi e Poco, ative também "Depuração USB (Configurações de segurança)" nas Opções do desenvolvedor, senão os toques podem falhar ou demorar.' 26 ($y + 4) 392 76 9 $false $cMuted $cBg))
  $ok = New-Object Windows.Forms.Button
  $ok.Text = 'Entendi'; $ok.DialogResult = 'OK'
  $ok.Location = [Drawing.Point]::new(24, 496); $ok.Size = [Drawing.Size]::new(392, 46)
  $ok.FlatStyle = 'Flat'; $ok.FlatAppearance.BorderSize = 0
  $ok.BackColor = $cAccent; $ok.ForeColor = [Drawing.Color]::White; $ok.UseVisualStyleBackColor = $false
  $ok.Font = [Drawing.Font]::new('Segoe UI', [single]11, [Drawing.FontStyle]::Bold); $ok.Cursor = 'Hand'
  $ok.Add_SizeChanged($RoundRegion)
  $h.Controls.Add($ok); $h.AcceptButton = $ok
  [void]$h.ShowDialog($form)
}

# ---------------------------------------------------------------- eventos
$flashTimer = New-Object Windows.Forms.Timer
$flashTimer.Interval = 1800
$flashTimer.Add_Tick({
  $flashTimer.Stop()
  if ($St.flashBtn) { $St.flashBtn.Text = $St.flashOld; $St.flashBtn = $null }
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 1500
$timer.Add_Tick({
  if ($St.busy) { return }
  Poll-Apps
  if ($St.proc) {
    if ($St.proc.HasExited) {
      $code = $St.proc.ExitCode; $log = ''
      try { if ($St.out.Wait(1500)) { $log = $St.out.Result + "`n" + $St.err.Result } } catch {}
      $St.proc = $null; $St.key = ''
      Refresh-Phone
      if ($code -ne 0) {
        $lines = @(($log -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 5)
        Msg ("O jogo foi fechado de forma inesperada.`nConfira se o cabo está bem conectado e se o celular está desbloqueado.`n`n" + ($lines -join "`n")) 'Warning'
      }
      Finish-Record
    }
    return
  }
  if ($St.pend) {
    if ($St.pend.t.IsCompleted) {
      $raw = $St.pend.t.Result; $St.pend = $null
      Apply-Devices $raw
    } elseif (((Get-Date) - $St.pend.at).TotalSeconds -gt 8) {
      try { $St.pend.p.Kill() } catch {}
      $St.pend = $null
    }
    return
  }
  Begin-Poll
})

$btnPlay.Add_Click({
  if ($St.state -eq 'error') { Prepare }
  elseif ($St.state -eq 'ready') { Start-Game }
})
$btnRefApps.Add_Click({ $St.appsFor = $null; Begin-Apps })
$btnRec.Add_Click({ Toggle-Rec })
$btnShot.Add_Click({ Take-Shot })
$btnFolder.Add_Click({ Open-GamesFolder })
$btnWifi.Add_Click({ Connect-Wifi })
$btnShort.Add_Click({ New-Shortcut })
$btnHelp.Add_Click({ Show-Help })
$form.Add_Shown({
  Update-Button; Update-Rec; Update-Secondary
  $form.Refresh()
  try { if (-not (Test-Path -LiteralPath $IcoFile)) { Save-Icon $IcoFile } } catch {}
  Prepare
})
$form.Add_FormClosing({
  Save-Settings; $timer.Stop()
  if ($St.rec -and $St.proc -and (-not $St.proc.HasExited)) {
    try { [void]$St.proc.CloseMainWindow(); [void]$St.proc.WaitForExit(5000) } catch {}
  }
})

Update-Button
Update-Rec
Update-Secondary
[Windows.Forms.Application]::Run($form)

} catch {
  [Windows.Forms.MessageBox]::Show("Ocorreu um erro inesperado:`n`n" + $_.Exception.Message, 'Espelhô') | Out-Null
}
