import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_refs.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> registerWithEmail({
    required String name,
    required String nickname,
    required String email,
    required String password,
    required bool acceptedTerms,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Cria/atualiza o perfil básico no Firestore
    final uid = cred.user!.uid;
    await usersCol().doc(uid).set({
      'displayName': name,
      'nickname': nickname,
      'email': email,
      'termsAcceptedAt': acceptedTerms ? FieldValue.serverTimestamp() : null,
      'seeds': {
        // opcional: estoque inicial simples
        'common': 3,
        'rare': 0,
        'epic': 0,
      },
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return cred;
  }

  Future<void> sendPasswordReset({required String email}) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() => _auth.signOut();
}