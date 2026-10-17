import 'package:addko/src/ui/plugin_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a bounded declarative page', () {
    final document = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'Example',
      'body': <String, Object?>{
        'type': 'column',
        'children': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': 'Hello',
          },
          <String, Object?>{
            'type': 'button',
            'label': 'Open',
            'action': 'open_details',
            'args': <Object?>['one'],
          },
        ],
      },
    });

    expect(document.title, 'Example');
    expect(document.body.type, 'column');
    expect(document.body.children, hasLength(2));
    expect(document.body.children.last.action, 'open_details');
    expect(document.body.children.last.actionArguments, <Object?>['one']);
  });

  test('parses form defaults and rejects duplicate names', () {
    final document = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'Form',
      'body': <String, Object?>{
        'type': 'column',
        'children': <Object?>[
          <String, Object?>{
            'type': 'input',
            'name': 'nickname',
            'value': 'Alex',
          },
          <String, Object?>{
            'type': 'switch',
            'name': 'notifications',
            'label': 'Notificações',
            'value': true,
          },
          <String, Object?>{
            'type': 'select',
            'name': 'theme',
            'options': <Object?>['Escuro', 'Claro'],
            'value': 'Escuro',
          },
        ],
      },
    });

    expect(document.initialFormValues, <String, Object?>{
      'nickname': 'Alex',
      'notifications': true,
      'theme': 'Escuro',
    });

    expect(
      () => PluginUiDocument.fromMap(<String, Object?>{
        'type': 'page',
        'title': 'Duplicado',
        'body': <String, Object?>{
          'type': 'column',
          'children': <Object?>[
            <String, Object?>{'type': 'input', 'name': 'same'},
            <String, Object?>{
              'type': 'checkbox',
              'name': 'same',
              'label': 'Mesmo nome',
            },
          ],
        },
      }),
      throwsA(isA<PluginUiException>()),
    );
  });

  test('parses tabs and validates their bounds', () {
    final document = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'Tabs',
      'body': <String, Object?>{
        'type': 'tabs',
        'index': 1,
        'tabs': <Object?>[
          <String, Object?>{
            'label': 'Home',
            'child': <String, Object?>{'type': 'text', 'text': 'A'},
          },
          <String, Object?>{
            'label': 'Profile',
            'child': <String, Object?>{'type': 'text', 'text': 'B'},
          },
        ],
      },
    });

    expect(document.body.type, 'tabs');
    expect(document.body.strings('labels'), <String>['Home', 'Profile']);
    expect(document.body.number('index'), 1);
    expect(document.body.children, hasLength(2));
  });

  test('rejects local asset traversal', () {
    expect(
      () => PluginUiDocument.fromMap(<String, Object?>{
        'type': 'page',
        'title': 'Bad asset',
        'body': <String, Object?>{
          'type': 'image',
          'src': 'asset:assets/../secret.png',
        },
      }),
      throwsA(isA<PluginUiException>()),
    );

    final safe = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'Safe asset',
      'body': <String, Object?>{
        'type': 'image',
        'src': 'asset:assets/logo.png',
      },
    });
    expect(safe.body.string('assetPath'), 'assets/logo.png');
  });

  test('rejects unsafe action method names', () {
    expect(
      () => PluginUiDocument.fromMap(<String, Object?>{
        'type': 'page',
        'title': 'Bad',
        'body': <String, Object?>{
          'type': 'button',
          'label': 'Bad',
          'action': '../escape',
        },
      }),
      throwsA(isA<PluginUiException>()),
    );
  });

  test('rejects unknown components', () {
    expect(
      () => PluginUiDocument.fromMap(<String, Object?>{
        'type': 'page',
        'title': 'Bad',
        'body': <String, Object?>{'type': 'webview'},
      }),
      throwsA(isA<PluginUiException>()),
    );
  });

  testWidgets('button action can replace the page returned by Lua', (tester) async {
    final first = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'First',
      'body': <String, Object?>{
        'type': 'button',
        'label': 'Next',
        'action': 'next_page',
      },
    });

    String? calledMethod;
    await tester.pumpWidget(
      MaterialApp(
        home: PluginUiPage(
          initialDocument: first,
          allowNetworkImages: false,
          onAction: (method, arguments) async {
            calledMethod = method;
            return <String, Object?>{
              'type': 'page',
              'title': 'Second',
              'body': <String, Object?>{
                'type': 'text',
                'text': 'Changed by Lua',
              },
            };
          },
        ),
      ),
    );

    expect(find.text('First'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(calledMethod, 'next_page');
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Changed by Lua'), findsOneWidget);
  });

  testWidgets('push and pop keep an internal mini-app navigation stack', (tester) async {
    final first = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'Home',
      'body': <String, Object?>{
        'type': 'button',
        'label': 'Details',
        'action': 'details',
        'navigation': 'push',
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PluginUiPage(
          initialDocument: first,
          allowNetworkImages: false,
          onAction: (method, arguments) async {
            return <String, Object?>{
              'type': 'page',
              'title': 'Details',
              'body': <String, Object?>{
                'type': 'button',
                'label': 'Back inside app',
                'navigation': 'pop',
              },
            };
          },
        ),
      ),
    );

    await tester.tap(find.text('Details').last);
    await tester.pumpAndSettle();
    expect(find.text('Back inside app'), findsOneWidget);

    await tester.tap(find.text('Back inside app'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets('tabs switch locally without calling Lua', (tester) async {
    final document = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'Tabs',
      'body': <String, Object?>{
        'type': 'tabs',
        'tabs': <Object?>[
          <String, Object?>{
            'label': 'One',
            'child': <String, Object?>{'type': 'text', 'text': 'First tab'},
          },
          <String, Object?>{
            'label': 'Two',
            'child': <String, Object?>{'type': 'text', 'text': 'Second tab'},
          },
        ],
      },
    });

    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PluginUiPage(
          initialDocument: document,
          allowNetworkImages: false,
          onAction: (method, arguments) async {
            calls += 1;
            return null;
          },
        ),
      ),
    );

    expect(find.text('First tab'), findsOneWidget);
    expect(find.text('Second tab'), findsNothing);
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('Second tab'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('form values are submitted to the Lua action', (tester) async {
    final document = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'Profile',
      'body': <String, Object?>{
        'type': 'column',
        'children': <Object?>[
          <String, Object?>{
            'type': 'input',
            'name': 'nickname',
            'label': 'Nome',
            'value': 'Antes',
          },
          <String, Object?>{
            'type': 'switch',
            'name': 'remember',
            'label': 'Lembrar',
            'value': false,
          },
          <String, Object?>{
            'type': 'select',
            'name': 'theme',
            'label': 'Tema',
            'options': <Object?>['Escuro', 'Claro'],
            'value': 'Escuro',
          },
          <String, Object?>{
            'type': 'button',
            'label': 'Salvar',
            'action': 'save_profile',
            'submit_form': true,
          },
        ],
      },
    });

    List<Object?>? receivedArguments;
    await tester.pumpWidget(
      MaterialApp(
        home: PluginUiPage(
          initialDocument: document,
          allowNetworkImages: false,
          onAction: (method, arguments) async {
            expect(method, 'save_profile');
            receivedArguments = arguments;
            return null;
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'Depois');
    await tester.tap(find.text('Lembrar'));
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(receivedArguments, hasLength(1));
    expect(receivedArguments!.single, <String, Object?>{
      'nickname': 'Depois',
      'remember': true,
      'theme': 'Escuro',
    });
  });

  testWidgets('search submits the current form automatically', (tester) async {
    final document = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'Search',
      'body': <String, Object?>{
        'type': 'search',
        'name': 'query',
        'hint': 'Buscar',
        'action': 'search',
      },
    });

    List<Object?>? receivedArguments;
    await tester.pumpWidget(
      MaterialApp(
        home: PluginUiPage(
          initialDocument: document,
          allowNetworkImages: false,
          onAction: (method, arguments) async {
            expect(method, 'search');
            receivedArguments = arguments;
            return null;
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'lua');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(receivedArguments, hasLength(1));
    expect(receivedArguments!.single, <String, Object?>{'query': 'lua'});
  });

  testWidgets('network images stay blocked without network permission', (tester) async {
    final document = PluginUiDocument.fromMap(<String, Object?>{
      'type': 'page',
      'title': 'Image',
      'body': <String, Object?>{
        'type': 'image',
        'src': 'https://example.com/picture.png',
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PluginUiPage(
          initialDocument: document,
          allowNetworkImages: false,
          onAction: (method, arguments) async => null,
        ),
      ),
    );

    expect(
      find.text('Imagem de rede bloqueada: permissão network necessária'),
      findsOneWidget,
    );
  });
}
