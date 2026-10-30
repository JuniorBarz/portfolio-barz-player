# Barz Player — portfólio técnico

Aplicativo Flutter para reprodução contínua de mídia em telas Android, com sincronização de playlist, armazenamento local e recuperação automática de falhas.

## Problema

Telas de comunicação digital precisam continuar exibindo conteúdo mesmo quando a rede oscila, um arquivo falha ou o aplicativo é reiniciado. A solução também precisa limitar downloads simultâneos, preservar espaço em disco e reportar o estado atual sem interromper a reprodução.

## Solução

O aplicativo recebe um endereço configurado pelo operador, consulta a playlist, baixa os arquivos necessários para uma pasta privada e reproduz a fila local. A camada de reprodução aplica timeouts, repetição controlada, descarte de eventos antigos e telemetria assíncrona.

## Principais recursos

- reprodução de vídeo e imagem em tela cheia;
- cache local com nomes de arquivo normalizados;
- sincronização periódica sem sobreposição de execuções;
- recuperação de mídia inválida ou indisponível;
- telemetria de estado sem bloquear a interface;
- inicialização após o boot, quando habilitada;
- testes de API, download, armazenamento, fila e widgets.

## Arquitetura

`lib/models` representa a mídia. `lib/services` concentra API, download, persistência, telemetria e coordenação da fila. `lib/player` mantém o ciclo de vida do player. `lib/main.dart` reúne configuração e navegação.

## Como executar

1. Instale Flutter 3.41.6 ou compatível e o Android SDK.
2. Execute `flutter pub get`.
3. Rode `flutter test` e `flutter analyze`.
4. Inicie com `flutter run` em um dispositivo Android.
5. Informe host, porta e canal de um ambiente de demonstração controlado por você; nenhum valor vem preenchido.

O cliente valida esses três campos e consulta `GET /api/screens/{canal}/playlist`. Os caminhos de status e reprodução seguem o mesmo contrato público. O pacote Android desta edição usa exclusivamente `dev.juniorbarz.portfolio.player`, evitando colisão com qualquer instalação privada.

## Segurança e privacidade

Esta edição não contém credenciais, endereços internos, dados de clientes, histórico do projeto privado nem infraestrutura empresarial. Os testes usam endereços reservados para documentação. O tráfego HTTP em texto claro permanece habilitado apenas para demonstrar integração com uma rede local controlada; em produção, deve ser substituído por HTTPS autenticado.

## Limitações

- não inclui servidor, painel administrativo ou conteúdo real;
- não é um sistema de gerenciamento de dispositivos;
- a inicialização após boot depende das regras da versão do Android;
- a compilação de release deste exemplo não deve usar assinatura de debug;
- o endpoint informado pelo usuário deve implementar o contrato demonstrativo descrito acima;
- esta edição aceita HTTP local para a demonstração, mas URLs absolutas de mídia precisam usar HTTPS.

## Minha participação

Projeto de autoria própria: arquitetura Flutter, integração HTTP, cache, fila resiliente, telemetria, automação Android e testes.

## Uso e contribuições

Código publicado somente para avaliação de portfólio. Não aceita contribuições. Consulte [PORTFOLIO_NOTICE.md](PORTFOLIO_NOTICE.md).
