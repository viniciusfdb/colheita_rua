import 'package:cloud_firestore/cloud_firestore.dart';

final db = FirebaseFirestore.instance;

CollectionReference<Map<String, dynamic>> usersCol() => db.collection('users');
CollectionReference<Map<String, dynamic>> runsCol() => db.collection('runs');
CollectionReference<Map<String, dynamic>> plantsCol() => db.collection('plants');
CollectionReference<Map<String, dynamic>> actionsCol() => db.collection('actions');
CollectionReference<Map<String, dynamic>> seedTypesCol() => db.collection('seed_types');