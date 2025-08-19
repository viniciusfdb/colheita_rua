import 'package:flutter/material.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termos de Uso')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Termos de uso do Colheita de Rua (MVP)\n\n'
              '- Você concorda em compartilhar dados de localização para funcionamento do jogo.\n'
              '- Não use o app para atividades ilegais ou perigosas.\n'
              '- Esses termos podem mudar no futuro.\n',
        ),
      ),
    );
  }
}