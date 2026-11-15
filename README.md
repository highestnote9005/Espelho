# Espelhô

Jogue o jogo do seu celular Android na tela do PC com Windows, de um jeito simples. Um programa com janela própria, feito para jogar junto: uma pessoa toca no celular e a outra usa mouse e teclado (ou um controle) ao mesmo tempo.

Escrito em C# com a interface nativa do Windows (WinForms). Não precisa de PowerShell nem de instalar nada além do próprio programa.

![Ícone do Espelhô](logo-espelho.png)

## Recursos

- **Instalação automática:** na primeira vez, o programa baixa sozinho o que precisa.
- **Detecção do celular em tempo real,** com o nome do aparelho e instruções na tela.
- **Escolha o jogo na lista** e ele abre sozinho no celular ao clicar em JOGAR.
- **Suporte a controle** de videogame (Xbox, PlayStation ou genérico).
- **Mostrar toques** na tela, para quem está assistindo.
- **Gravar a partida e tirar prints,** salvos na pasta `Jogos` da Área de Trabalho.
- **Jogar sem cabo (Wi-Fi)** com um clique.
- **Criar atalho** com ícone próprio na Área de Trabalho.
- Ajustes de qualidade, tela cheia, som e mais, que o programa lembra.

## Como criar o Espelho.exe

Você não precisa instalar nada: o compilador já vem com o Windows 10 e o Windows 11.

1. Deixe `Compilar.bat`, `Espelho.cs` e `espelho.ico` juntos na mesma pasta.
2. Dê dois cliques em `Compilar.bat`.
3. Quando aparecer "Pronto!", o `Espelho.exe` estará na mesma pasta.

## Como usar

1. Dê dois cliques no `Espelho.exe`. Na primeira vez ele baixa o necessário (precisa de internet).
2. No celular, ative a **Depuração USB** (o botão **Ajuda** do programa mostra como).
3. Conecte o cabo USB e toque em **Permitir** no celular.
4. Escolha o jogo e clique em **JOGAR**.

> Na primeira vez, o Windows pode mostrar "O Windows protegeu o computador" porque o programa não tem assinatura digital. Clique em **Mais informações** e depois em **Executar assim mesmo**.

## Assinatura digital

Por padrão o `Espelho.exe` não tem assinatura, e o Windows pode avisar na primeira execução.

- **No seu computador:** depois de compilar, o `Compilar.bat` oferece assinar o programa. Isso cria um certificado próprio e confiável só neste PC (`Assinar.bat`).
- **Em outro computador:** leve o `Espelho.exe`, o `Espelho.cer` e o `ConfiarNoCertificado.bat`, e rode o `ConfiarNoCertificado.bat` uma vez. Ou simplesmente compile lá, porque um programa criado no próprio computador não gera aviso.
- **Para o público em geral:** é preciso um certificado emitido por uma autoridade (por exemplo, o SignPath Foundation, que oferece assinatura gratuita para projetos de código aberto, ou um certificado OV pago). Mesmo assim, o aviso do SmartScreen pode aparecer até o programa ganhar reputação.

## Requisitos

- Windows 10 ou 11 (o .NET Framework 4.x já vem instalado).
- Celular Android com Depuração USB ativada e cabo que transfira dados.
- Internet apenas na primeira execução.

## Como funciona

O Espelhô é uma interface gráfica que usa o [scrcpy](https://github.com/Genymobile/scrcpy), que faz o espelhamento e o controle do Android, e o `adb` que acompanha o scrcpy. O scrcpy não é redistribuído neste repositório: é baixado do repositório oficial na primeira execução e guardado na pasta `programa`.

## Créditos

- [scrcpy](https://github.com/Genymobile/scrcpy), de Genymobile, licença Apache 2.0.

## Licença

[MIT](LICENSE)
