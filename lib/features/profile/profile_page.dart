import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/firestore_refs.dart';
import '../../core/utils/slug.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameCtrl = TextEditingController();
  final _nickCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // --- [NOVO] Estado para Dropdowns de País/Estado/Cidade ---
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;



  bool _initialized = false;
  bool _saving = false;

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return usersCol().doc(uid).get();
  }


  Future<void> _saveProfile() async {
    try {
      setState(() => _saving = true);
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final displayName = _nameCtrl.text.trim();
      final nickname = _nickCtrl.text.trim();
      final email = _emailCtrl.text.trim();

      final countryName = (_selectedCountry ?? '').trim();
      final stateName = (_selectedState ?? '').trim();
      final cityName = (_selectedCity ?? '').trim();

      final Map<String, dynamic> updates = {
        if (displayName.isNotEmpty) 'displayName': displayName,
        'nickname': nickname,
        // Localização (salvamos nome + chave normalizada)
        if (countryName.isNotEmpty) 'countryName': countryName,
        if (stateName.isNotEmpty) 'stateName': stateName,
        if (cityName.isNotEmpty) 'cityName': cityName,
        if (countryName.isNotEmpty) 'countryKey': slugify(countryName),
        if (stateName.isNotEmpty) 'stateKey': slugify(stateName),
        if (cityName.isNotEmpty) 'cityKey': slugify(cityName),
      };

      await usersCol().doc(uid).set(updates, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil atualizado com sucesso.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar perfil: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePasswordFlow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.email ?? '').isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faça login novamente para alterar a senha.')),
      );
      return;
    }

    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alterar senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha atual',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nova senha',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmar nova senha',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (ok != true) return;

    if (newCtrl.text.isEmpty || newCtrl.text != confirmCtrl.text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('As senhas não conferem.')),
      );
      return;
    }

    try {
      setState(() => _saving = true);
      // Reautentica
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: currentCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      // Atualiza senha
      await user.updatePassword(newCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha alterada com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao alterar senha: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateEmailFlow() async {
    final user = FirebaseAuth.instance.currentUser!;
    final newEmail = _emailCtrl.text.trim();
    if (newEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um e-mail válido.')),
      );
      return;
    }

    final pwdCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar alteração de e-mail'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Por segurança, confirme sua senha atual.'),
            const SizedBox(height: 12),
            TextField(
              controller: pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha atual',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      setState(() => _saving = true);
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: pwdCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      await user.verifyBeforeUpdateEmail(newEmail);

      // espelha informativo no Firestore (não é fonte de verdade)
      await usersCol().doc(user.uid).set({'email': newEmail}, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail atualizado. Verifique sua caixa de entrada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar e-mail: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  /// Salva as alterações do perfil e, se o e-mail mudou, dispara o fluxo de atualização (com reautenticação).
  Future<void> _onSavePressed() async {
    final currentEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final newEmail = _emailCtrl.text.trim();

    // Primeiro salva Nome/Apelido/Localização
    await _saveProfile();

    // Se o e-mail mudou, ativa o fluxo seguro de troca de e-mail (com confirmação de senha)
    if (newEmail.isNotEmpty && newEmail != currentEmail) {
      await _updateEmailFlow();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nickCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService(); // mantido para ações (reset de senha)
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      body: FutureBuilder(
        future: _loadProfile(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = (snap.data?.data() ?? {});
          final displayName = (data['displayName'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'Jogador').toString();
          final nickname = (data['nickname'] ?? '').toString();
          final email = FirebaseAuth.instance.currentUser?.email ?? '-';
          final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;

          final countryKey = (data['countryKey'] ?? '').toString();
          final stateKey = (data['stateKey'] ?? '').toString();
          final cityKey = (data['cityKey'] ?? '').toString();
          final totalDistanceKm = (data['totalDistanceKm'] ?? 0).toDouble();
          final totalPoints = (data['totalPoints'] ?? 0).toInt();

          if (!_initialized) {
            _nameCtrl.text = displayName;
            _nickCtrl.text = nickname;
            _emailCtrl.text = email == '-' ? '' : email;
            // Inicializa seleção dos dropdowns com os nomes, se existirem
            if ((data['countryName'] ?? '').toString().isNotEmpty) {
              _selectedCountry = (data['countryName'] as String);
            }
            if ((data['stateName'] ?? '').toString().isNotEmpty) {
              _selectedState = (data['stateName'] as String);
            }
            if ((data['cityName'] ?? '').toString().isNotEmpty) {
              _selectedCity = (data['cityName'] as String);
            }
            _initialized = true;
          }

          String firstName() {
            final parts = displayName.trim().split(' ');
            return parts.isNotEmpty ? parts.first : displayName;
          }

          String initials() {
            final parts = displayName.trim().split(' ');
            if (parts.isEmpty) return 'J';
            final a = parts.first.isNotEmpty ? parts.first[0] : '';
            final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
            final res = (a + b).toUpperCase();
            return res.isEmpty ? 'J' : res;
          }

          return SafeArea(
            top: true,
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.green,
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                        child: photoUrl == null
                            ? Text(
                                initials(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Seu Perfil',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // [ATUALIZADO 2025-08-19] Perfil (layout unificado e moderno)
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Cabeçalho
                        Text(
                          'Informações do perfil',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                        ),
                        const SizedBox(height: 16),
                        // Nome
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nome',
                            hintText: 'Seu nome completo',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Apelido
                        TextField(
                          controller: _nickCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Apelido',
                            hintText: 'Como você quer aparecer',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // E-mail (largura total). Se mudar, confirmaremos a senha ao salvar.
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'E-mail',
                            hintText: 'seu@email.com',
                            helperText: 'Ao salvar, se o e-mail mudou, pediremos sua senha para confirmar.',
                            helperMaxLines: 2,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Botão salvar
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _saving ? null : _onSavePressed,
                            icon: _saving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save),
                            label: const Text('Salvar alterações'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Ações
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _changePasswordFlow,
                          icon: const Icon(Icons.vpn_key),
                          label: const Text('Alterar senha'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (FirebaseAuth.instance.currentUser?.email != null) {
                              await auth.sendPasswordReset(email: FirebaseAuth.instance.currentUser!.email!);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('E-mail de redefinição enviado.')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.lock_reset),
                          label: const Text('Redefinir senha'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            // [MODIFICADO 2025-08-18] Sign-out robusto + navegação segura
                            try {
                              // Se houver provedor externo (Google/Facebook/Apple), faça signOut aqui também.

                              await FirebaseAuth.instance.signOut();

                              if (!context.mounted) return;
                              Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erro ao sair: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Sair da conta'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        backgroundColor: const Color(0xFFF7F8F7),
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black54,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        onTap: (index) async {
          if (index == 0) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              try {
                Navigator.of(context).pushReplacementNamed('/home');
              } catch (_) {}
            }
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}