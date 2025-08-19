import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import 'terms_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _auth = AuthService();
  final _name = TextEditingController();
  final _nick = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _accepted = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _nick.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você precisa aceitar os termos de uso.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await _auth.registerWithEmail(
        name: _name.text.trim(),
        nickname: _nick.text.trim(),
        email: _email.text.trim(),
        password: _password.text.trim(),
        acceptedTerms: _accepted,
      );

      // Garante que o doc em users/{uid} existe e possui seeds iniciais
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        await docRef.set({
          'displayName': _name.text.trim(),
          'nickname': _nick.text.trim(),
          'email': _email.text.trim(),
          'seeds': {
            'common': 3,
            'rare': 0,
            'epic': 0,
          },
          'termsAcceptedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastro realizado com sucesso. Faça login.')),
      );

      // Fluxo definido: após cadastro, sair e voltar para a tela de login
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao registrar: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTerms() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermsPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: 8),
          TextField(controller: _nick, decoration: const InputDecoration(labelText: 'Nickname')),
          const SizedBox(height: 8),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'E-mail')),
          const SizedBox(height: 8),
          TextField(controller: _password, decoration: const InputDecoration(labelText: 'Senha'), obscureText: true),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(value: _accepted, onChanged: (v) => setState(() => _accepted = v ?? false)),
              const Text('Aceito os '),
              TextButton(onPressed: _openTerms, child: const Text('termos de uso')),
            ],
          ),
          const SizedBox(height: 16),
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(onPressed: _register, child: const Text('Cadastrar')),
        ],
      ),
    );
  }
}