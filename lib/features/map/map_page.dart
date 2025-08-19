import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show ImageFilter;
import '../run/run_summary_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng? _currentPosition;
  final MapController _mapController = MapController();
  double _currentZoom = 17;
  LatLng _lastCenter = const LatLng(0, 0);
  bool _mapReady = false;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  final List<LatLng> _track = [];
  double _distanceMeters = 0;
  Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  bool _running = false;

  // Dados da corrida (para resumo)
  DateTime? _runStartAt;
  String? _currentRunId;
  final List<String> _plantedIds = [];
  final List<LatLng> _plantedPoints = [];
  final List<Map<String, dynamic>> _plantedWithType = [];
  final List<Map<String, dynamic>> _waterPointsRun = [];
  final List<Map<String, dynamic>> _stealPointsRun = [];
  final List<Map<String, dynamic>> _harvestPointsRun = [];


  // Contadores de ações desta corrida
  int _wateredCountRun = 0;
  int _stolenCountRun = 0;
  int _harvestedCountRun = 0;
  int _totalPointsRun = 0;

  // Acúmulo de distância desde o último plantio
  double _distSinceLastPlant = 0;

  // Marcadores das mudas plantadas
  final List<Marker> _plantMarkers = [];
  // [FX] Marcadores animados de plantio recente
  final List<_PlantedFx> _plantedFx = [];

  void _spawnPlantedFx(LatLng p, String type) {
    _spawnFx(p, kind: 'plant', type: type, points: _pointsPerFruit(type));
  }

  void _spawnFx(LatLng p, {required String kind, required String type, required int points}) {
    final fx = _PlantedFx(
      position: p,
      kind: kind,
      type: type,
      opacity: 1.0,
      offsetLat: 0.0,
      points: points,
    );
    _plantedFx.add(fx);
    // 24ms ~ 41fps, animação mais suave e lenta (~3s)
    Timer? timer;
    timer = Timer.periodic(const Duration(milliseconds: 24), (t) {
      fx.offsetLat += 0.000015; // sobe devagar
      fx.opacity -= 0.008;      // fade lento (~3s)
      if (fx.opacity <= 0) {
        _plantedFx.remove(fx);
        t.cancel();
        if (mounted) setState(() {});
        return;
      }
      if (mounted) setState(() {});
    });
  }

  // Plantio
  LatLng? _lastPlantedPoint;
  DateTime? _lastPlantAt;
  int seedsCommon = 0;
  int seedsRare = 0;
  int seedsEpic = 0;
  int get _seedsTotal => seedsCommon + seedsRare + seedsEpic;

  // Simulação de movimento
  bool _simulating = false;
  Timer? _simTimer;
  final Random _rng = Random();
  double _simBearing = 0; // em graus

  final _dist = const Distance();
  double _distBetween(LatLng a, LatLng b) => _dist.as(LengthUnit.Meter, a, b);

  // [MOD] Pontos por fruto por raridade (lê de seed_types com fallback 1/3/5)
  int _pointsPerFruit(String type) {
    final v = _seedTypes[type]?['pointsPerFruit'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    switch (type) {
      case 'rare':
        return 3;
      case 'epic':
        return 5;
      default:
        return 1;
    }
  }
// [/MOD]

  // Mundo vivo: tipos de semente, plantas próximas e seus marcadores
  Map<String, Map<String, dynamic>> _seedTypes = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _plantsSub;
  final List<Map<String, dynamic>> _nearbyPlants = []; // cada item: {id, data}
  final List<Marker> _worldMarkers = [];
  final double _visibleRadiusMeters = 300.0; // ~300m (economia de leituras)
  // Interações automáticas por proximidade
  final Map<String, DateTime> _plantCooldown = {}; // cooldown por planta
  final double _interactionRadiusMeters = 15.0; // raio para interagir automaticamente
  double _gpsAccuracyMeters = 20.0; // última acurácia reportada pelo GPS
  // Evita acionar a mesma planta mais de uma vez em paralelo
  final Set<String> _inFlightPlants = <String>{};

  @override
  void initState() {
    super.initState();
    _listenUserInventory();
    _getLocation();
    _loadSeedTypes();
  }

  Future<void> _getLocation() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });

    _lastCenter = _currentPosition!;
    if (_mapReady) {
      _mapController.move(_currentPosition!, _currentZoom);
    }
    _listenPlantsAround();
  }

  Future<void> _loadSeedTypes() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('seed_types').get();
      for (final d in snap.docs) {
        final m = d.data();
        _seedTypes[d.id] = m;
      }
    } catch (_) {
      // manter vazio se falhar; usaremos defaults
    }
  }

  void _listenPlantsAround() {
    if (_currentPosition == null) return;
    _plantsSub?.cancel();

    final center = _currentPosition!;
    // ~1km em graus
    final latDelta = 0.009; // ~1km
    final lonDelta = 0.009 / max<double>(cos(center.latitude * pi / 180.0), 0.1);
    final minLat = center.latitude - latDelta;
    final maxLat = center.latitude + latDelta;

    final query = FirebaseFirestore.instance
        .collection('plants')
        // [MOD] Leia somente plantas ativas para economizar leituras
        .where('state', whereIn: ['growing', 'ripe'])
        .where('lat', isGreaterThan: minLat)
        .where('lat', isLessThan: maxLat);

    _plantsSub = query.snapshots().listen((qs) async {
      _nearbyPlants.clear();
      _worldMarkers.clear();

      for (final doc in qs.docs) {
        final data = doc.data();
        final lat = (data['lat'] as num).toDouble();
        final lng = (data['lng'] as num).toDouble();
        final p = LatLng(lat, lng);
        // filtro por longitude e distância real
        if ((p.longitude - center.longitude).abs() > lonDelta) continue;
        final dist = _distBetween(center, p);
        if (dist > _visibleRadiusMeters) continue;

        final enriched = await _deriveAndMaybePersistState(doc.id, data);
        // Esconde apenas no cliente quando a regra mandar ocultar
        if (_shouldHidePlant(enriched)) {
          continue;
        }
        _nearbyPlants.add({'id': doc.id, 'data': enriched});

        final marker = _buildPlantMarker(doc.id, enriched, p);
        _worldMarkers.add(marker);
      }

      if (mounted) setState(() {});
    });
  }

  Future<Map<String, dynamic>> _deriveAndMaybePersistState(String id, Map<String, dynamic> data) async {
    final type = (data['type'] ?? 'common') as String;
    final cfg = _seedTypes[type] ?? const {
      'growHours': 12,
      'fruits': 1,
      'stealable': true,
      'minWaters': 0,
    };

    final growHours = (cfg['growHours'] as num).toInt();
    final minWaters = (cfg['minWaters'] as num).toInt();

    DateTime? plantedAt;
    final pa = data['plantedAt'];
    if (pa is Timestamp) plantedAt = pa.toDate();
    if (pa is DateTime) plantedAt = pa;

    final waterCount = (data['waterCount'] ?? 0) is int
        ? data['waterCount'] as int
        : (data['waterCount'] as num?)?.toInt() ?? 0;
    final state = (data['state'] ?? 'growing') as String;

    String derived = state;
    if (state != 'dead' && plantedAt != null) {
      final now = DateTime.now();
      final grewAt = plantedAt.add(Duration(hours: growHours));
      final diedAt = plantedAt.add(const Duration(hours: 24));

      if (waterCount == 0 && now.isAfter(diedAt)) {
        derived = 'dead';
      } else if (now.isAfter(grewAt) && waterCount >= minWaters) {
        // pronta para colher
        if (state != 'harvested') {
          derived = 'ripe';
        }
      } else {
        derived = 'growing';
      }

      // Persistir "dead" para não ficar mudando no cliente
      if (derived == 'dead' && state != 'dead') {
        try {
          await FirebaseFirestore.instance.collection('plants').doc(id).update({
            'state': 'dead',
            'deadAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }
      // Persistir "ripe" quando atingir tempo + regas (sem depender do cliente do dono)
      if (derived == 'ripe' && state != 'ripe' && state != 'dead' && state != 'harvested') {
        try {
          await FirebaseFirestore.instance.collection('plants').doc(id).update({
            'state': 'ripe',
            'ripeAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }
    }

    final enriched = Map<String, dynamic>.from(data);
    enriched['derivedState'] = derived;
    enriched['growHours'] = growHours;
    enriched['minWaters'] = minWaters;
    return enriched;
  }

  bool _shouldHidePlant(Map<String, dynamic> data) {
    // Se o servidor explicitamente ocultar no futuro, respeitamos:
    if (data['hidden'] == true) return true;

    final state = (data['state'] ?? data['derivedState'] ?? 'growing') as String;
    if (state != 'dead') return false;

    DateTime? deadAt;
    final da = data['deadAt'];
    if (da is Timestamp) deadAt = da.toDate();
    if (da is DateTime) deadAt = da;

    if (deadAt == null) return false;
    // Só esconde depois 12h de mortas
    return DateTime.now().difference(deadAt) > const Duration(hours: 12);
  }

  // Helper para reconstruir marcadores do mundo a partir de _nearbyPlants
  void _rebuildWorldMarkersFromNearby() {
    _worldMarkers
      ..clear()
      ..addAll(_nearbyPlants.map((e) {
        final id = e['id'] as String;
        final data = Map<String, dynamic>.from(e['data'] as Map);
        final lat = (data['lat'] as num).toDouble();
        final lng = (data['lng'] as num).toDouble();
        return _buildPlantMarker(id, data, LatLng(lat, lng));
      }));
  }

  Marker _buildPlantMarker(String id, Map<String, dynamic> data, LatLng p) {
    final derived = (data['derivedState'] ?? data['state'] ?? 'growing') as String;

    // Cor baseada na RARIDADE (tipo) e não mais no estado de crescimento
    final type = (data['type'] ?? 'common') as String;
    Color color;
    // Estados finais ainda sobrescrevem para cinza
    if (derived == 'dead') {
      color = Colors.grey; // planta morta
    } else {
      switch (type) {
        case 'rare':
          color = Colors.blueAccent;      // rara = azul
          break;
        case 'epic':
          color = Colors.deepPurpleAccent; // épica = roxo
          break;
        default:
          color = Colors.green;            // comum = verde
      }
    }

    // waterCount para o badge
    final wcRaw = data['waterCount'];
    final int waterCount = wcRaw is int ? wcRaw : (wcRaw is num ? wcRaw.toInt() : 0);

    // fruits restantes (para badge de colheita) — mostra somente quando ripe
    final frRaw = data['fruits'];
    final int fruits = frRaw is int ? frRaw : (frRaw is num ? frRaw.toInt() : 1);
    final stRaw = data['stolenCount'];
    final int stolen = stRaw is int ? stRaw : (stRaw is num ? stRaw.toInt() : 0);
    final int fruitsLeft = max(fruits - stolen, 0);

    return Marker(
      point: p,
      width: 34,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Badge de frutas restantes (🍒), só se ripe e há frutas
          if (derived == 'ripe' && fruitsLeft > 0)
            Positioned(
              right: -6,
              bottom: -12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black87, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🍒', style: TextStyle(fontSize: 10, height: 1.0)),
                    Text(
                      fruitsLeft.toString(),
                      style: const TextStyle(color: Colors.black87, fontSize: 10, height: 1.0),
                    ),
                  ],
                ),
              ),
            ),
          if (waterCount > 0)
            Positioned(
              right: -6,
              top: -12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black87, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💧', style: TextStyle(fontSize: 10, height: 1.0)),
                    Text(
                      waterCount.toString(),
                      style: const TextStyle(color: Colors.black87, fontSize: 10, height: 1.0),
                    ),
                  ],
                ),
              ),
            ),
          // ícone da planta
          Center(child: Icon(Icons.spa, size: 28, color: color)),
        ],
      ),
    );
  }


  Future<void> _maybeAutoInteractAtPosition(LatLng p) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;

    // raio efetivo leva em conta a acurácia do GPS (cap em 20m)
    final double effRadius = max(_interactionRadiusMeters, min(_gpsAccuracyMeters, 20.0));

    // [MOD] Evitar erro de "Concurrent modification": cria snapshot imutável da lista
    final itemsSnapshot = List<Map<String, dynamic>>.from(_nearbyPlants);
    // [/MOD]

    final now = DateTime.now();
    for (final item in itemsSnapshot) {
      final String id = item['id'] as String;
      // Se já estamos processando essa planta em paralelo, ignora
      if (_inFlightPlants.contains(id)) continue;
      final Map<String, dynamic> data = Map<String, dynamic>.from(item['data'] as Map);
      final lat = (data['lat'] as num).toDouble();
      final lng = (data['lng'] as num).toDouble();
      final plantPos = LatLng(lat, lng);

      // Distância real
      final d = _distBetween(p, plantPos);
      if (d > effRadius) continue;

      // Cooldown por planta (12s)
      final last = _plantCooldown[id];
      if (last != null && now.difference(last) < const Duration(seconds: 12)) {
        continue;
      }

      final derived = (data['derivedState'] ?? data['state'] ?? 'growing') as String;
      final owner = data['ownerUid'] as String?;
      final type = (data['type'] ?? 'common') as String;
      final cfg = _seedTypes[type] ?? const {'fruits': 1, 'stealable': true};

      final stealable = (cfg['stealable'] as bool?) ?? true;

      // Evita regar imediatamente após o próprio plantio (grace period)
      DateTime? plantedAt;
      final pa = data['plantedAt'];
      if (pa is Timestamp) plantedAt = pa.toDate();
      if (pa is DateTime) plantedAt = pa;
      final int wc = (data['waterCount'] ?? 0) is int ? data['waterCount'] as int : (data['waterCount'] as num?)?.toInt() ?? 0;
      if (owner == me && wc == 0 && plantedAt != null && now.difference(plantedAt) < const Duration(seconds: 8)) {
        // pula interação para não regar instantaneamente
        continue;
      }

      try {
        if (derived == 'growing') {
          _inFlightPlants.add(id);
          _plantCooldown[id] = now; // cooldown imediato para evitar duplo disparo
          await _actionWater(id);
        } else if (derived == 'ripe') {
          if (owner == me) {
            _inFlightPlants.add(id);
            _plantCooldown[id] = now;
            await _actionHarvest(id);
          } else if (stealable) {
            _inFlightPlants.add(id);
            _plantCooldown[id] = now;
            // [MOD] roubo busca fruits/maxStealable direto do doc
            await _actionSteal(id);
            // [/MOD]
          }
        }
      } catch (_) {
        // silencioso
      } finally {
        _inFlightPlants.remove(id);
      }
    }
  }

  Future<void> _actionWater(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    double? _lat, _lng;
    try {
      final db = FirebaseFirestore.instance;
      String type = 'common';
      await db.runTransaction((tx) async {
        final ref = db.collection('plants').doc(id);
        final snap = await tx.get(ref);
        final data = snap.data() as Map<String, dynamic>?;
        if (data == null) {
          throw Exception('Planta inexistente');
        }
        final state = (data['state'] ?? 'growing') as String;
        _lat = (data['lat'] as num?)?.toDouble();
        _lng = (data['lng'] as num?)?.toDouble();
        // Captura tipo da planta
        type = (data['type'] ?? 'common') as String;
        // só rega se não estiver finalizada
        if (state == 'dead' || state == 'harvested') {
          throw Exception('Planta finalizada');
        }
        tx.update(ref, {
          'waterCount': FieldValue.increment(1),
          'lastWaterAt': FieldValue.serverTimestamp(),
        });
      });

      await FirebaseFirestore.instance.collection('actions').add({
        'type': 'water',
        'uid': user.uid,
        'plantId': id,
        'at': FieldValue.serverTimestamp(),
        'points': 1,
        'runId': _currentRunId,
        'lat': _lat,
        'lng': _lng,
        'plantType': type,
        'ppf': 1,
      });

      if (_lat != null && _lng != null) {
        _waterPointsRun.add({'lat': _lat, 'lng': _lng, 'type': type});
        _spawnFx(LatLng(_lat!, _lng!), kind: 'water', type: type, points: 1);
      }

      _wateredCountRun += 1;
      _totalPointsRun += 1; // rega = 1 ponto fixo
      if (mounted) setState(() {});
    } catch (_) {
      return; // silencioso
    }
  }

  Future<void> _actionHarvest(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    double? _lat, _lng;
    try {
      final db = FirebaseFirestore.instance;
      String plantType = 'common';
      int fruits = 1;
      int stolen = 0;

      await db.runTransaction((tx) async {
        final ref = db.collection('plants').doc(id);
        final snap = await tx.get(ref);
        final data = snap.data() as Map<String, dynamic>?;
        if (data == null) {
          throw Exception('Planta inexistente');
        }
        final owner = data['ownerUid'] as String?;
        if (owner != user.uid) {
          throw Exception('Apenas o dono pode colher');
        }
        final state = (data['state'] ?? 'growing') as String;
        if (state == 'harvested' || state == 'dead') {
          throw Exception('Planta já finalizada');
        }

        // Captura dados para pontuação
        plantType = (data['type'] ?? 'common') as String;
        fruits = (data['fruits'] is num) ? (data['fruits'] as num).toInt() : 1;
        stolen = (data['stolenCount'] is num) ? (data['stolenCount'] as num).toInt() : 0;
        _lat = (data['lat'] as num?)?.toDouble();
        _lng = (data['lng'] as num?)?.toDouble();
        tx.update(ref, {
          'state': 'harvested',
          'harvestedAt': FieldValue.serverTimestamp(),
          'harvestedBy': user.uid,
        });
      });

      final remaining = max(fruits - stolen, 0);
      final pointsPerFruit = _pointsPerFruit(plantType); // <-- NOVO
      final points = remaining * pointsPerFruit;        // <-- AJUSTADO

      await FirebaseFirestore.instance.collection('actions').add({
        'type': 'harvest',
        'uid': user.uid,
        'plantId': id,
        'at': FieldValue.serverTimestamp(),
        // [MOD] pontos pelo que sobrou
        'points': points,
        'runId': _currentRunId,
        'lat': _lat,
        'lng': _lng,
        'plantType': plantType,
        'ppf': pointsPerFruit,
      });

      if (_lat != null && _lng != null) {
        _harvestPointsRun.add({'lat': _lat, 'lng': _lng, 'type': plantType});
        _spawnFx(LatLng(_lat!, _lng!), kind: 'harvest', type: plantType, points: points);
      }

      _harvestedCountRun += 1;
      _totalPointsRun += points; // soma total da colheita
      if (mounted) setState(() {});
    } catch (_) {
      return; // silencioso
    }
  }

  // [MOD] roubo respeita maxStealable e pontua por raridade
  Future<void> _actionSteal(String id) async {
// [/MOD]
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    double? _lat, _lng;
    try {
      final db = FirebaseFirestore.instance;
      int pointsPerFruit = 1; // default; será ajustado pelo tipo
      String plantType = 'common';
      int fruits = 1;

      await db.runTransaction((tx) async {
        final ref = db.collection('plants').doc(id);
        final snap = await tx.get(ref);
        final data = snap.data() as Map<String, dynamic>? ?? {};

        plantType = (data['type'] ?? 'common') as String;
        _lat = (data['lat'] as num?)?.toDouble();
        _lng = (data['lng'] as num?)?.toDouble();

        pointsPerFruit = _pointsPerFruit(plantType);
        fruits = (data['fruits'] is num) ? (data['fruits'] as num).toInt() : 1;
        final int maxStealable = (data['maxStealable'] is num)
            ? (data['maxStealable'] as num).toInt()
            : fruits; // fallback seguro
        final int stolen = (data['stolenCount'] is num) ? (data['stolenCount'] as num).toInt() : 0;

        // Respeita teto de roubo
        if (stolen >= maxStealable) {
          throw Exception('Nada para roubar');
        }

        tx.update(ref, {
          'stolenCount': FieldValue.increment(1),
        });

        // Finaliza planta apenas se realmente não sobra nenhum fruto
        if (stolen + 1 >= fruits) {
          tx.update(ref, {
            'state': 'harvested',
            'harvestedAt': FieldValue.serverTimestamp(),
            'harvestedBy': user.uid,
          });
        }
      });

      await db.collection('actions').add({
        'type': 'steal',
        'uid': user.uid,
        'plantId': id,
        'at': FieldValue.serverTimestamp(),
        // [MOD] pontuação conforme raridade
        'points': pointsPerFruit,
        'runId': _currentRunId,
        'lat': _lat,
        'lng': _lng,
        'plantType': plantType,
        'ppf': pointsPerFruit,
      });

      if (_lat != null && _lng != null) {
        _stealPointsRun.add({'lat': _lat, 'lng': _lng, 'type': plantType});
        _spawnFx(LatLng(_lat!, _lng!), kind: 'steal', type: plantType, points: pointsPerFruit);
      }

      _stolenCountRun += 1;
      _totalPointsRun += pointsPerFruit; // cada roubo rende ppf
      if (mounted) setState(() {});
    } catch (_) {
      return; // silencioso
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _listenUserInventory() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    _userSub?.cancel();
    _userSub = docRef.snapshots().listen((snap) async {
      final data = snap.data() ?? {};
      final rawSeeds = data['seeds'];
      Map<String, dynamic> seeds = rawSeeds is Map ? Map<String, dynamic>.from(rawSeeds as Map) : <String, dynamic>{};

      // Se o doc do usuário ainda não tem 'seeds', inicializa com comuns/rara/épica
      if (!snap.exists || seeds.isEmpty) {
        await docRef.set({
          'seeds': {'common': 3, 'rare': 0, 'epic': 0},
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        seeds = {'common': 3, 'rare': 0, 'epic': 0};
      } else {
        // Garante chaves ausentes
        seeds['common'] = seeds['common'] ?? 0;
        seeds['rare'] = seeds['rare'] ?? 0;
        seeds['epic'] = seeds['epic'] ?? 0;
      }

      final c = seeds['common'];
      final r = seeds['rare'];
      final e = seeds['epic'];
      seedsCommon = c is int ? c : (c is num ? c.toInt() : 0);
      seedsRare   = r is int ? r : (r is num ? r.toInt() : 0);
      seedsEpic   = e is int ? e : (e is num ? e.toInt() : 0);
      if (mounted) setState(() {});
    });
  }

  void _zoomIn() {
    setState(() {
      _currentZoom += 1;
      if (_mapReady) {
        _mapController.move(_lastCenter, _currentZoom);
      }
    });
  }

  void _zoomOut() {
    setState(() {
      _currentZoom -= 1;
      if (_mapReady) {
        _mapController.move(_lastCenter, _currentZoom);
      }
    });
  }

  void _goToMyLocation() {
    if (_currentPosition != null && _mapReady) {
      _mapController.move(_currentPosition!, _currentZoom);
    }
  }

  Future<bool> _ensureLocationPermissions({required bool background}) async {
    // 1) Serviço de localização ligado?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      try { await Geolocator.openLocationSettings(); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ative a Localização para iniciar a corrida.')),
        );
      }
      return false;
    }

    // 2) Checa/solicita permissão
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // 3) Se bloqueado permanentemente, leva às configurações
    if (permission == LocationPermission.deniedForever) {
      try { await Geolocator.openAppSettings(); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização negada. Ajuste nas Configurações.')),
        );
      }
      return false;
    }

    // Se for apenas foreground, basta whileInUse ou always em qualquer plataforma
    if (!background) {
      return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
    }

    // 4) Background: comportamento por plataforma
    if (Platform.isAndroid) {
      // Android: WhileInUse funciona em background quando usamos foreground service
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        return true;
      }
      // Tenta pedir de novo
      final again = await Geolocator.requestPermission();
      final ok = (again == LocationPermission.whileInUse || again == LocationPermission.always);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permita localização para registrar a corrida em segundo plano.')),
        );
      }
      return ok;
    } else {
      // iOS: Always é o ideal, mas vamos aceitar WhileInUse (com aviso) para permitir iniciar
      if (permission == LocationPermission.always) return true;
      if (permission == LocationPermission.whileInUse) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('iOS: com "Durante o uso" o tracking pode pausar em segundo plano. Para experiência contínua, permita "Sempre" nas Configurações.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return true;
      }
      // Tenta pedir novamente
      final again = await Geolocator.requestPermission();
      if (again == LocationPermission.always) return true;
      if (again == LocationPermission.whileInUse) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('iOS: com "Durante o uso" o tracking pode pausar em segundo plano. Para experiência contínua, permita "Sempre" nas Configurações.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return true;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização é necessária para iniciar a corrida.')),
        );
      }
      return false;
    }
  }

  Future<void> _startRun() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faça login para iniciar uma corrida e salvar no histórico.')),
      );
      return;
    }
    // iOS: se permissão for whileInUse, mostrar diálogo antes de pedir always/background
    if (Platform.isIOS) {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse) {
        // Mostrar diálogo para o usuário
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Permissão de Localização"),
            content: const Text(
              "Para rastrear sua corrida em segundo plano, é recomendado permitir 'Sempre' nas configurações. "
              "Você pode ajustar isso agora ou continuar apenas com o rastreamento em uso.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(true);
                },
                child: const Text("Entendo"),
              ),
              TextButton(
                onPressed: () async {
                  await Geolocator.openAppSettings();
                  Navigator.of(ctx).pop(false);
                },
                child: const Text("Ajustar"),
              ),
            ],
          ),
        );
        if (proceed != true) {
          // Usuário escolheu "Ajustar" ou cancelou, não inicia corrida.
          return;
        }
        // Usuário escolheu "Entendo", prossegue normalmente.
      }
    }
    // Garante permissões adequadas para rodar em background
    final ok = await _ensureLocationPermissions(background: true);
    if (!ok) return;
    if (_running) return;
    _running = true;
    _distanceMeters = 0;
    _track.clear();
    _distSinceLastPlant = 0;
    _plantMarkers.clear();
    _plantedIds.clear();
    _plantedPoints.clear();
    _plantedWithType.clear();
    _waterPointsRun.clear();
    _stealPointsRun.clear();
    _harvestPointsRun.clear();
    _totalPointsRun = 0;
    _runStartAt = DateTime.now();
    _wateredCountRun = 0;
    _stolenCountRun = 0;
    _harvestedCountRun = 0;
    // [MOD] Cria run draft para termos runId durante a corrida
    _currentRunId = null;
    final authUser2 = FirebaseAuth.instance.currentUser;
    if (authUser2 != null) {
      final draft = await FirebaseFirestore.instance.collection('runs').add({
        'uid': authUser2.uid,
        'startedAt': DateTime.now(),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'running',
      });
      _currentRunId = draft.id;
    }
    _stopwatch.reset();
    _stopwatch.start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

    // Configurações de localização com suporte a background (Android: foreground service; iOS: background updates)
    final locationSettings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
            intervalDuration: const Duration(seconds: 2),
            // Mantém um serviço em primeiro plano com notificação persistente enquanto a corrida está ativa
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationText: 'Rastreando sua corrida…',
              notificationTitle: 'Colheita na Rua',
              enableWakeLock: true,
              notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          );

    _posSub = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen(_onLocationUpdate);
    setState(() {});
  }

  Future<void> _stopRun() async {
    if (!_running) return;
    _running = false;
    await _posSub?.cancel();
    _posSub = null;
    _stopwatch.stop();
    _ticker?.cancel();
    if (_simulating) {
      _stopSimulation();
    }

    // Persistir corrida em `runs` e ir para o resumo
    final user = FirebaseAuth.instance.currentUser;
    final endedAt = DateTime.now();
    final startedAt = _runStartAt ?? endedAt.subtract(Duration(milliseconds: _stopwatch.elapsedMilliseconds));
    final durationMs = _stopwatch.elapsedMilliseconds;

    final List<Map<String, dynamic>> path = _track
        .map((e) => {'lat': e.latitude, 'lng': e.longitude})
        .toList(growable: false);

    String? runId;
    if (user != null) {
      if (_currentRunId != null) {
        // [MOD] Atualiza o run draft existente
        await FirebaseFirestore.instance.collection('runs').doc(_currentRunId).update({
          'uid': user.uid,
          'distanceMeters': _distanceMeters,
          'durationMs': durationMs,
          'startedAt': startedAt,
          'endedAt': endedAt,
          'path': path,
          'plantedCount': _plantedIds.length,
          'plantedIds': _plantedIds,
          'wateredCount': _wateredCountRun,
          'stolenCount': _stolenCountRun,
          'harvestedCount': _harvestedCountRun,
          'plantedPoints': _plantedPoints
              .map((e) => {'lat': e.latitude, 'lng': e.longitude})
              .toList(),
          'plantedWithType': List<Map<String, dynamic>>.from(_plantedWithType),
          'waterPoints': List<Map<String, dynamic>>.from(_waterPointsRun),
          'stealPoints': List<Map<String, dynamic>>.from(_stealPointsRun),
          'harvestPoints': List<Map<String, dynamic>>.from(_harvestPointsRun),
          'totalPoints': _totalPointsRun,
          'status': 'finished',
        });
        runId = _currentRunId;
      } else {
        // [MOD] Fallback: cria o run agora se não havia draft
        final runRef = await FirebaseFirestore.instance.collection('runs').add({
          'uid': user.uid,
          'distanceMeters': _distanceMeters,
          'durationMs': durationMs,
          'startedAt': startedAt,
          'endedAt': endedAt,
          'path': path,
          'plantedCount': _plantedIds.length,
          'plantedIds': _plantedIds,
          'createdAt': FieldValue.serverTimestamp(),
          'wateredCount': _wateredCountRun,
          'stolenCount': _stolenCountRun,
          'harvestedCount': _harvestedCountRun,
          'plantedPoints': _plantedPoints
              .map((e) => {'lat': e.latitude, 'lng': e.longitude})
              .toList(),
          'plantedWithType': List<Map<String, dynamic>>.from(_plantedWithType),
          'waterPoints': List<Map<String, dynamic>>.from(_waterPointsRun),
          'stealPoints': List<Map<String, dynamic>>.from(_stealPointsRun),
          'harvestPoints': List<Map<String, dynamic>>.from(_harvestPointsRun),
          'totalPoints': _totalPointsRun,
          'status': 'finished',
        });
        runId = runRef.id;
      }
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(arguments: {
          'plantedWithType': _plantedWithType,
          'waterPoints': _waterPointsRun,
          'stealPoints': _stealPointsRun,
          'harvestPoints': _harvestPointsRun,
        }),
        builder: (_) => RunSummaryPage(
          runId: runId,
          distanceMeters: _distanceMeters,
          durationMs: durationMs,
          plantedCount: _plantedIds.length,
          plantedPoints: List<LatLng>.from(_plantedPoints),
          path: List<LatLng>.from(_track),
          startedAt: startedAt,
          endedAt: endedAt,
          wateredCount: _wateredCountRun,
          stolenCount: _stolenCountRun,
          harvestedCount: _harvestedCountRun,
        ),
      ),
    );

    _currentRunId = null; // [MOD] libera o runId após finalizar

    setState(() {});
  }

  Future<void> _onLocationUpdate(Position pos) async {
    final p = LatLng(pos.latitude, pos.longitude);
    _gpsAccuracyMeters = pos.accuracy;
    if (_track.isNotEmpty) {
      final d = _distBetween(_track.last, p);
      _distanceMeters += d;
      _distSinceLastPlant += d;
    }
    _track.add(p);
    _lastCenter = p;
    _currentPosition = p;
    if (_mapReady) {
      _mapController.move(p, _currentZoom);
    }

    // Tentativa de plantio automático a cada 100m (menos gravações)
    if (_running && _seedsTotal > 0 && _distSinceLastPlant >= 100.0) {
      final now = DateTime.now();
      final canByTime = _lastPlantAt == null ? true : now.difference(_lastPlantAt!).inMilliseconds >= 2000;

      if (canByTime) {
        if (_seedsTotal <= 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sem sementes disponíveis.')),
            );
          }
        } else {
          final plantedType = await _plantHere(p);
          if (plantedType != null) {
            _lastPlantAt = now;
            _distSinceLastPlant = 0; // zera após plantar
            _addPlantMarker(p, plantedType); // cor por raridade
          }
        }
      }
    }

    await _maybeAutoInteractAtPosition(p);
    setState(() {});
  }

  Future<void> _onSimulatedPoint(LatLng p) async {
    if (_track.isNotEmpty) {
      final d = _distBetween(_track.last, p);
      _distanceMeters += d;
      _distSinceLastPlant += d;
    }
    _track.add(p);
    _lastCenter = p;
    _currentPosition = p;
    if (_mapReady) {
      _mapController.move(p, _currentZoom);
    }

    // Tentativa de plantio automático a cada 100m (menos gravações)
    if (_running && _seedsTotal > 0 && _distSinceLastPlant >= 100.0) {
      final now = DateTime.now();
      final canByTime = _lastPlantAt == null ? true : now.difference(_lastPlantAt!).inMilliseconds >= 2000;

      if (canByTime) {
        if (_seedsTotal <= 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sem sementes disponíveis.')),
            );
          }
        } else {
          final plantedType = await _plantHere(p);
          if (plantedType != null) {
            _lastPlantAt = now;
            _distSinceLastPlant = 0; // zera após plantar
            _addPlantMarker(p, plantedType); // cor por raridade
          }
        }
      }
    }

    await _maybeAutoInteractAtPosition(p);
    if (mounted) setState(() {});
  }
  void _addPlantMarker(LatLng p, String type) {
    Color color;
    switch (type) {
      case 'rare':
        color = Colors.blueAccent;      // rara = azul
        break;
      case 'epic':
        color = Colors.deepPurpleAccent; // épica = roxo
        break;
      default:
        color = Colors.green;            // comum = verde
    }
    _plantMarkers.add(
      Marker(
        point: p,
        width: 28,
        height: 28,
        child: Icon(Icons.spa, size: 28, color: color),
      ),
    );
    if (mounted) setState(() {});
  }

  void _toggleSimulation() {
    if (_simulating) {
      _stopSimulation();
    } else {
      _startSimulation();
    }
  }

  void _startSimulation() {
    if (_currentPosition == null) return;
    _simulating = true;
    // Se não estiver correndo, inicia a corrida para testar o plantio.
    if (!_running) {
      _startRun();
    }
    // Bearing inicial aleatório
    _simBearing = _rng.nextDouble() * 360.0;
    // Modo manual: sem timer automático; movimento pelos botões (up/left/right/down)
    _simTimer?.cancel();
    _simTimer = null;
    if (mounted) setState(() {});
  }

  void _stopSimulation() {
    _simTimer?.cancel();
    _simTimer = null;
    _simulating = false;
    // Opcional: parar a corrida também
    // _stopRun();
    if (mounted) setState(() {});
  }

  void _simStep() {
    if (_currentPosition == null) return;
    // Variação suave do rumo (-40..+40 graus)
    _simBearing += (_rng.nextDouble() * 80.0) - 40.0;
    // Normaliza ângulo
    while (_simBearing < 0) _simBearing += 360.0;
    while (_simBearing >= 360.0) _simBearing -= 360.0;

    // Calcula próximo ponto a ~100m do atual na direção _simBearing (para testar o novo plantio)
    final next = _dist.offset(_currentPosition!, 100.0, _simBearing);
    _onSimulatedPoint(next);
  }

  // --- Manual simulation controls ---
  void _simStepBearing(double bearingDeg, {double meters = 35}) {
    if (_currentPosition == null) return;
    final next = _dist.offset(_currentPosition!, meters, bearingDeg);
    _onSimulatedPoint(next);
  }

  // Passo fino para cima (ajuste mais preciso)
  void _simUp() => _simStepBearing(0, meters: 10);
  void _simRight() => _simStepBearing(90, meters: 10); // passo fino ~10m
  // Passo padrão/mais longo para baixo
  void _simDown() => _simStepBearing(180, meters: 35);
  void _simLeft() => _simStepBearing(270); // passo padrão ~35m

  String _cellId(LatLng p) => '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';

  Future<String?> _plantHere(LatLng p) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(user.uid);

      String? plantId;
      String? plantedType;

      await db.runTransaction((tx) async {
        final uSnap = await tx.get(userRef);
        final uData = uSnap.data() ?? {};
        final seeds = (uData['seeds'] ?? {}) as Map<String, dynamic>;
        int c = (seeds['common'] ?? 0) is int ? seeds['common'] as int : (seeds['common'] as num?)?.toInt() ?? 0;
        int r = (seeds['rare']   ?? 0) is int ? seeds['rare']   as int : (seeds['rare']   as num?)?.toInt() ?? 0;
        int e = (seeds['epic']   ?? 0) is int ? seeds['epic']   as int : (seeds['epic']   as num?)?.toInt() ?? 0;

        String seedType;
        if (e > 0) {
          seedType = 'epic';
        } else if (r > 0) {
          seedType = 'rare';
        } else if (c > 0) {
          seedType = 'common';
        } else {
          throw Exception('Sem sementes');
        }
        plantedType = seedType;

        Map<String, dynamic>? cfg = _seedTypes[seedType];
        cfg ??= () {
          switch (seedType) {
            case 'rare':
              return {
                'growHours': 24,
                'fruits': 8,
                'stealable': true,
                'minWaters': 2,
              };
            case 'epic':
              return {
                'growHours': 48,
                'fruits': 5,
                'stealable': true,
                'minWaters': 3,
              };
            default:
              return {
                'growHours': 12,
                'fruits': 10,
                'stealable': true,
                'minWaters': 1,
              };
          }
        }();

        final int growHours = (cfg['growHours'] as num).toInt();
        final int fruits = (cfg['fruits'] as num).toInt();
        final bool stealable = (cfg['stealable'] as bool? ?? true);
        final int minWaters = (cfg['minWaters'] as num).toInt();
        final int maxStealable = (cfg['maxStealable'] as num?)?.toInt() ?? fruits;

        final plantRef = db.collection('plants').doc();
        plantId = plantRef.id;
        tx.set(plantRef, {
          'ownerUid': user.uid,
          'type': seedType,
          'lat': p.latitude,
          'lng': p.longitude,
          'plantedAt': FieldValue.serverTimestamp(),
          'state': 'growing',
          'hidden': false,
          'waterCount': 0,
          'stolenCount': 0,
          'fruits': fruits,
          'stealable': stealable,
          'minWaters': minWaters,
          'growHours': growHours,
          'maxStealable': maxStealable,
        });

        final String fieldPath = seedType == 'epic'
            ? 'seeds.epic'
            : (seedType == 'rare' ? 'seeds.rare' : 'seeds.common');
        tx.update(userRef, {fieldPath: FieldValue.increment(-1)});
      });

      if (plantId != null) {
        await FirebaseFirestore.instance.collection('actions').add({
          'type': 'plant',
          'uid': FirebaseAuth.instance.currentUser!.uid,
          'plantId': plantId,
          'plantType': plantedType,
          'lat': p.latitude,
          'lng': p.longitude,
          'at': FieldValue.serverTimestamp(),
          'points': _pointsPerFruit(plantedType!),
          'runId': _currentRunId,
          'ppf': _pointsPerFruit(plantedType!),
        });
        _plantedIds.add(plantId!);
        _plantedPoints.add(p);
        _plantCooldown[plantId!] = DateTime.now();
        if (plantedType != null) {
          _plantedWithType.add({'lat': p.latitude, 'lng': p.longitude, 'type': plantedType});
        }
        // [FX] Spawn floating points animation
        if (plantedType != null) {
          _spawnPlantedFx(p, plantedType!);
          _totalPointsRun += _pointsPerFruit(plantedType!); // plant dá ppf por raridade
        }
      }

      // [FX] Removido SnackBar de "🌱 Plantada!"
      return plantedType;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível plantar: $e')),
        );
      }
      return null;
    }
  }

  String _formatElapsed() {
    final ms = _stopwatch.elapsedMilliseconds;
    final s = (ms ~/ 1000) % 60;
    final m = (ms ~/ 60000) % 60;
    final h = (ms ~/ 3600000);
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  String _formatPace() {
    if (_distanceMeters <= 1) return '--:--';
    final seconds = _stopwatch.elapsedMilliseconds ~/ 1000;
    final km = _distanceMeters / 1000.0;
    final pace = seconds / km; // sec per km
    final mm = (pace ~/ 60).toInt();
    final ss = (pace % 60).round();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(mm)}:${two(ss)}';
  }

  void _pauseOrResumeRun() {
    if (!_running) return;
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
      _ticker?.cancel();
      _posSub?.pause();
      if (_simulating) _simTimer?.cancel();
      setState(() {});
    } else {
      _stopwatch.start();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      _posSub?.resume();
      if (_simulating) {
        _simTimer?.cancel();
        _simTimer = Timer.periodic(const Duration(seconds: 2), (_) => _simStep());
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _userSub?.cancel();
    _ticker?.cancel();
    _simTimer?.cancel();
    _plantsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition!,
                    initialZoom: _currentZoom,
                    onMapEvent: (event) {
                      setState(() {
                        _lastCenter = event.camera.center;
                        _currentZoom = event.camera.zoom;
                      });
                    },
                    onMapReady: () {
                      setState(() {
                        _mapReady = true;
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.colheita_rua',
                    ),
                    if (_track.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _track,
                            strokeWidth: 4.0,
                            color: Colors.green,
                          ),
                        ],
                      ),
                    if (_worldMarkers.isNotEmpty)
                      MarkerLayer(markers: _worldMarkers),
                    if (_plantMarkers.isNotEmpty)
                      MarkerLayer(markers: _plantMarkers),
                    // [FX] Floating planted points animation markers
                    if (_plantedFx.isNotEmpty)
                      MarkerLayer(
                        markers: _plantedFx.map((fx) {
                          // Escolhe ícone/cor conforme a ação
                          IconData fxIcon;
                          Color fxColor;
                          if (fx.kind == 'water') {
                            fxIcon = Icons.water_drop;
                            fxColor = Colors.blue;
                          } else if (fx.kind == 'steal') {
                            fxIcon = Icons.flag;
                            fxColor = Colors.black87;
                          } else if (fx.kind == 'harvest') {
                            fxIcon = Icons.local_florist;
                            fxColor = Colors.orange;
                          } else {
                            // plant: cor por raridade
                            fxIcon = Icons.spa;
                            switch (fx.type) {
                              case 'rare':
                                fxColor = Colors.blueAccent;
                                break;
                              case 'epic':
                                fxColor = Colors.deepPurpleAccent;
                                break;
                              default:
                                fxColor = Colors.green;
                            }
                          }
                          final points = fx.points;
                          return Marker(
                            point: LatLng(fx.position.latitude + fx.offsetLat, fx.position.longitude),
                            width: 44,
                            height: 44,
                            child: Opacity(
                              opacity: fx.opacity.clamp(0.0, 1.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(fxIcon, color: fxColor, size: 16),
                                  Text(
                                    "+$points",
                                    style: TextStyle(
                                      color: fxColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentPosition!,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.person_pin_circle,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Distância grande no topo, sem fundo
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          shadows: [Shadow(blurRadius: 6, color: Colors.white, offset: Offset(0, 2))],
                        ),
                        children: [
                          TextSpan(
                            text: (_distanceMeters / 1000).toStringAsFixed(2),
                            style: const TextStyle(fontSize: 42),
                          ),
                          TextSpan(
                            text: ' km',
                            style: const TextStyle(fontSize: 22),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Adaptive glass (blur) HUD with 3 columns: distance, pace, seeds
                Positioned(
                  top: MediaQuery.of(context).padding.top + 62,
                  left: 20,
                  right: 20,
                  child: Builder(
                    builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final bg = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.45);
                      final fg = isDark ? Colors.white : Colors.black87;

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.black12,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Tempo
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatElapsed(),
                                        style: TextStyle(
                                          color: fg,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text('tempo', style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 12)),
                                    ],
                                  ),
                                ),
                                // Pace
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatPace(),
                                        style: TextStyle(
                                          color: fg,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text('min/km', style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 12)),
                                    ],
                                  ),
                                ),
                                // Sementes por raridade
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.spa, size: 16, color: Colors.green),
                                          SizedBox(width: 8),
                                          Icon(Icons.spa, size: 16, color: Colors.blueAccent),
                                          SizedBox(width: 8),
                                          Icon(Icons.spa, size: 16, color: Colors.deepPurpleAccent),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        child: Row(
                                          children: [
                                            Text('$seedsCommon', style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700)),
                                            const SizedBox(width: 16),
                                            Text('$seedsRare', style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700)),
                                            const SizedBox(width: 16),
                                            Text('$seedsEpic', style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 20,
                  top: MediaQuery.of(context).size.height * 0.40,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        heroTag: 'simulateToggle',
                        onPressed: _toggleSimulation,
                        mini: true,
                        child: Icon(_simulating ? Icons.pause : Icons.auto_graph),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        heroTag: 'zoomIn',
                        onPressed: _zoomIn,
                        mini: true,
                        child: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        heroTag: 'zoomOut',
                        onPressed: _zoomOut,
                        mini: true,
                        child: const Icon(Icons.remove),
                      ),
                    ],
                  ),
                ),
                if (_simulating)
                  Positioned(
                    left: 20,
                    bottom: 32 + 112 + 24, // acima dos botões principais
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Up
                        _SimGlassButton(icon: Icons.keyboard_arrow_up, onTap: _simUp),
                        const SizedBox(height: 8),
                        // Middle row: left and right
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SimGlassButton(icon: Icons.keyboard_arrow_left, onTap: _simLeft),
                            const SizedBox(width: 12),
                            _SimGlassButton(icon: Icons.keyboard_arrow_right, onTap: _simRight),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Down
                        _SimGlassButton(icon: Icons.keyboard_arrow_down, onTap: _simDown),
                      ],
                    ),
                  ),
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // End run (glass button with glass effect)
                      GestureDetector(
                        onTap: _running ? _stopRun : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child:
                            BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                              child: Builder(
                                builder: (context) {
                                  final isDark = Theme.of(context).brightness == Brightness.dark;
                                  final bg = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.45);
                                  final fg = isDark ? Colors.white : Colors.black87;
                                  return Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12, width: 1),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 6)),
                                      ],
                                    ),
                                    child: Center(
                                      child: Icon(Icons.close, color: fg, size: 30),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Play/Pause (glass big button)
                      GestureDetector(
                        onTap: _running ? _pauseOrResumeRun : _startRun,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(60),
                          child:
                            BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                              child: Builder(
                                builder: (context) {
                                  final isDark = Theme.of(context).brightness == Brightness.dark;
                                  final bg = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.45);
                                  final fg = isDark ? Colors.white : Colors.black87;
                                  return Container(
                                    width: 112,
                                    height: 112,
                                    decoration: BoxDecoration(
                                      color: bg,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12, width: 1),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 14, offset: const Offset(0, 8)),
                                      ],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _running && _stopwatch.isRunning ? Icons.pause : Icons.play_arrow,
                                        size: 48,
                                        color: fg,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // My Location (glass button, same style as End)
                      GestureDetector(
                        onTap: _goToMyLocation,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: Builder(
                              builder: (context) {
                                final isDark = Theme.of(context).brightness == Brightness.dark;
                                final bg = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.45);
                                final fg = isDark ? Colors.white : Colors.black87;
                                return Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: isDark ? Colors.white10 : Colors.black12, width: 1),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 6)),
                                    ],
                                  ),
                                  child: Center(
                                    child: Icon(Icons.my_location, color: fg, size: 28),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 20,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.chevron_left, color: Colors.black, size: 32),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ),
              ],
            ),
    );
  }
}

// [FX] Classe privada para animação de ações (top-level)
class _PlantedFx {
  LatLng position;
  String kind; // 'plant' | 'water' | 'steal' | 'harvest'
  String type; // raridade: 'common' | 'rare' | 'epic'
  double opacity;
  double offsetLat;
  int points; // pontos fixados no spawn
  _PlantedFx({
    required this.position,
    required this.kind,
    required this.type,
    required this.opacity,
    required this.offsetLat,
    required this.points,
  });
}

// --- Simulação: botão de vidro para o D-pad ---
class _SimGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SimGlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = (isDark ? Colors.black : Colors.white).withOpacity(0.45);
    final fg = isDark ? Colors.white : Colors.black87;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12, width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(icon, color: fg, size: 28),
          ),
        ),
      ),
    );
  }
}