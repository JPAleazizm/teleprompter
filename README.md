<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

# teleprompter

Um widget de teleprompter com gravação de vídeo integrada para Flutter.

Este pacote fornece uma página completa (`TeleprompterPage`) que exibe o
texto do teleprompter, controle de rolagem, pré-visualização da câmera,
gravação em múltiplos takes e concatenador de vídeos final (mp4) usando
`ffmpeg_kit_flutter_new`.

## Recursos

- Teleprompter com rolagem automática configurável (velocidade, fonte, tamanho
  e cor).
- Gravação em múltiplos takes com visualização de miniaturas.
- Concatenador de takes em um único arquivo mp4.
- Callback `onVideoReady` para receber o arquivo final assim que estiver
  pronto.

## Instalação

Adicione ao seu `pubspec.yaml`:

```yaml
dependencies:
  teleprompter: 0.0.4
```

E execute `flutter pub get`.

> Observação: o pacote depende de plugins que exigem configuração nativa
> (câmera, ffmpeg kit). Consulte a documentação desses plugins se encontrar
> problemas na build.

## Uso

Exemplo mínimo de como abrir a página do teleprompter e receber o arquivo
final quando pronto:

```dart
import 'package:flutter/material.dart';
import 'package:teleprompter/teleprompter.dart';

// Em algum lugar do seu app:
Navigator.push(context, MaterialPageRoute(
  builder: (_) => TeleprompterPage(
    text: 'Olá! Este é o texto do teleprompter.',
    maxDurationSeconds: 120,
    onVideoReady: (file) async {
      // file é um XFile apontando para o mp4 final.
      debugPrint('Vídeo gerado em ${file.path}');
      // Você pode mover, enviar para servidor, mostrar um preview, etc.
    },
  ),
));
```

### `onVideoReady`

O callback tem a forma `FutureOr<void> Function(XFile finalVideo)` e é
chamado quando a concatenação dos takes terminou com sucesso. Você pode
realizar operações assíncronas dentro do callback (por exemplo upload). Erros
lançados no callback são capturados pelo pacote e não interrompem o fluxo.

## Permissões e configuração nativa

- Android: adicione permissões de câmera e microfone no `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

- iOS: adicione as chaves em `Info.plist`:

```
NSCameraUsageDescription
NSMicrophoneUsageDescription
```

- ffmpeg: o pacote usa `ffmpeg_kit_flutter_new` para concatenar os arquivos.
  Verifique a documentação do plugin para instruções adicionais sobre a
  configuração de binários em cada plataforma.

## Boas práticas

- Teste em dispositivo real sempre que possível (câmera e ffmpeg podem não
  funcionar corretamente no emulador).
- Use o callback `onVideoReady` para mover ou fazer upload do arquivo final
  e libere recursos temporários conforme necessário.

## Exemplos

Veja a pasta `example/` deste repositório para um app completo mostrando o
fluxo de uso do `TeleprompterPage`.

## Contribuição

- Abra issues para bugs e sugestões.
- PRs são bem-vindas. Mantenha testes mínimos e atualize a documentação quando
  adicionar ou alterar comportamento.

## Licença

Consulte o arquivo `LICENSE` neste repositório.
