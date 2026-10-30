# Barz Player

Aplicativo Flutter para reproduzir imagens e vídeos continuamente em telas Android, mantendo uma fila local utilizável quando a conexão oscila.

> Demonstração independente de portfólio. Não contém servidor, credenciais, dados de clientes, endereços internos nem histórico do projeto privado.

## Problema

Uma tela de comunicação digital precisa baixar conteúdo, preservar arquivos válidos, recuperar-se de falhas e continuar reproduzindo sem exigir intervenção constante. Telemetria e sincronização não podem interromper o fluxo principal.

## Solução implementada

O operador informa host, porta e canal. O Player consulta uma playlist demonstrativa, valida os itens, baixa arquivos para a pasta privada do aplicativo e reproduz a fila local. Sincronização, telemetria e eventos pendentes são tratados de forma assíncrona e com limites explícitos.

## Tecnologias

- Flutter e Dart;
- plugins Android para vídeo, armazenamento, preferências, informações do pacote e inicialização após boot;
- cliente HTTP com timeouts e validação de URL;
- testes de serviços, modelos, armazenamento, reprodução e widgets.

## Funcionalidades demonstradas

- reprodução de imagens e vídeos em tela cheia;
- cache local com nomes de arquivo normalizados;
- downloads com progresso e limite de concorrência;
- sincronização periódica sem execuções sobrepostas;
- recuperação de mídia inválida ou indisponível;
- fila local de eventos de reprodução com limite e reenvio;
- telemetria de estado em modo best-effort;
- inicialização após o boot quando habilitada.

## Arquitetura e decisões

- `lib/models` representa itens de mídia;
- `lib/services` concentra API, download, armazenamento, telemetria e fila de eventos;
- `lib/player` controla o ciclo de vida de imagens e vídeos;
- `lib/main.dart` reúne configuração e navegação.

O pacote Android desta edição é `dev.juniorbarz.portfolio.player`, separado de instalações privadas.

## Contrato demonstrativo

O cliente consulta `GET /api/screens/{canal}/playlist` e envia status e eventos aos caminhos correspondentes. Esse contrato pertence somente a esta demonstração do Player.

O repositório **Barz Media API** é outro exemplo independente de portfólio. Nesta fase, os dois projetos não são apresentados como uma integração end-to-end nem como contratos mutuamente compatíveis.

## Como executar

Pré-requisitos: Flutter 3.41.6 ou compatível, Android SDK e dispositivo ou emulador Android.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Na tela inicial, informe host, porta e canal de um serviço demonstrativo sob seu controle. Nenhum endereço vem preenchido.

## Testes e validação

Os testes cobrem validação de endpoints, parsing da playlist, download, armazenamento, duração de mídia, fila de eventos, telemetria e interface inicial. O exportador de portfólio publica somente os arquivos aprovados por manifesto e hash.

## Segurança e privacidade

Os testes usam endereços reservados para documentação. URLs absolutas de mídia precisam usar HTTPS. O aplicativo ainda permite HTTP em texto claro para conversar com um serviço local controlado; isso é uma concessão da demonstração e não um padrão adequado para produção.

## Limitações

- não inclui servidor, painel administrativo, conteúdo real ou gerenciamento de dispositivos;
- o contrato HTTP é ilustrativo e não foi validado contra o Backend deste portfólio;
- não há autenticação, autorização, criptografia de aplicação ou garantia de entrega exatamente uma vez;
- inicialização após boot depende da versão e das políticas de energia do Android;
- a configuração de release usa assinatura de debug para avaliação local e não deve ser distribuída;
- resiliência local não equivale a operação validada em produção.

## Minha participação e direitos

Arquitetura Flutter, integração HTTP, cache, fila resiliente, telemetria, automação Android, testes e documentação: Junior Barz.

Código apresentado somente para leitura e avaliação profissional. Não aceita contribuições. Consulte [PORTFOLIO_NOTICE.md](PORTFOLIO_NOTICE.md).
