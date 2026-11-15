# Espelhô

Jogue o jogo do seu celular Android na tela do PC com Windows, de um jeito simples: um arquivo, dois cliques e uma janela fácil de usar. Feito para jogar junto: uma pessoa toca no celular e a outra usa mouse e teclado (ou um controle) ao mesmo tempo.

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

## Como usar

1. Baixe o `Espelho.bat` (em **Releases**, ou pelo botão **Code > Download ZIP**).
2. Coloque em uma pasta, por exemplo `Espelho`, e dê dois cliques.
3. No celular, ative a **Depuração USB** (o botão **Ajuda** do programa mostra como).
4. Conecte o cabo USB, toque em **Permitir** no celular, escolha o jogo e clique em **JOGAR**.

> Na primeira vez, o Windows pode mostrar "O Windows protegeu o computador". Clique em **Mais informações** e depois em **Executar assim mesmo**.

## Requisitos

- Windows 10 ou 11 (o PowerShell 5.1 já vem instalado).
- Celular Android com Depuração USB ativada e cabo que transfira dados.
- Internet apenas na primeira execução.

## Como funciona

O Espelhô é uma interface gráfica escrita em PowerShell dentro de um único `.bat`. Ele baixa e usa o [scrcpy](https://github.com/Genymobile/scrcpy), que faz o espelhamento e o controle do Android, e o `adb` que acompanha o scrcpy. O scrcpy não é redistribuído neste repositório: é baixado do repositório oficial na primeira execução.

## Créditos

- [scrcpy](https://github.com/Genymobile/scrcpy), de Genymobile, licença Apache 2.0.

## Licença

[MIT](LICENSE)
