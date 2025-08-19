import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui' as ui; // [MODIFICADO 2025-08-18] Para usar ui.Path no sketch

class RunSummaryPage extends StatelessWidget {
  final String? runId;
  final double distanceMeters;
  final int durationMs;
  final int plantedCount;
  final int wateredCount;
  final int stolenCount;
  final int harvestedCount;
  final List<LatLng> plantedPoints;
  final List<LatLng> path;
  final DateTime startedAt;
  final DateTime endedAt;

  const RunSummaryPage({
    super.key,
    required this.runId,
    required this.distanceMeters,
    required this.durationMs,
    required this.plantedCount,
    required this.wateredCount,
    required this.stolenCount,
    required this.harvestedCount,
    required this.plantedPoints,
    required this.path,
    required this.startedAt,
    required this.endedAt,
  });

  // [MOD] Soma pontos das actions no intervalo da corrida (filtra por at e uid)
  Future<int> _fetchTotalPoints(DateTime start, DateTime end) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('actions')
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('at', isLessThanOrEqualTo: Timestamp.fromDate(end));
    if (uid != null) {
      q = q.where('uid', isEqualTo: uid);
    }
    final snap = await q.get();
    int total = 0;
    for (final d in snap.docs) {
      final v = d.data()['points'];
      if (v is int) {
        total += v;
      } else if (v is num) {
        total += v.toInt();
      }
    }
    return total;
  }

  // [MOD] Soma pontos das actions pelo runId (consulta mais precisa e barata)
  Future<int> _fetchTotalPointsByRunId(String runId) async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('actions')
        .where('runId', isEqualTo: runId);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      q = q.where('uid', isEqualTo: uid);
    }
    final snap = await q.get();
    int total = 0;
    for (final d in snap.docs) {
      final v = d.data()['points'];
      if (v is int) {
        total += v;
      } else if (v is num) {
        total += v.toInt();
      }
    }
    return total;
  }

  // [MOD] Prefere valor denormalizado do run, com fallback para actions
  Future<int?> _getRunTotalPointsDenorm(String runId) async {
    final doc = await FirebaseFirestore.instance.collection('runs').doc(runId).get();
    final data = doc.data();
    if (data == null) return null;
    final v = data['totalPoints'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  Future<int> _getScorePreferDenorm(String runId) async {
    final den = await _getRunTotalPointsDenorm(runId);
    if (den != null) return den;
    return _fetchTotalPointsByRunId(runId);
  }

  String _fmtDuration(int ms) {
    final s = (ms ~/ 1000) % 60;
    final m = (ms ~/ 60000) % 60;
    final h = (ms ~/ 3600000);
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  String _fmtPace(double meters, int ms) {
    if (meters <= 0 || ms <= 0) return '-';
    final paceSecPerKm = (ms / 1000) / (meters / 1000);
    final min = paceSecPerKm ~/ 60;
    final sec = (paceSecPerKm % 60).round();
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}/km';
  }

  String _fmtDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // Formato curto: HH:mm:ss • dd/MM
  String _fmtShortDateTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final MM = dt.month.toString().padLeft(2, '0');
    return '$hh:$mm:$ss • $dd/$MM';
  }

  // Formato longo PT-BR: 01 de Dezembro de 2025 às 12:33
  String _fmtPtBrLong(DateTime dt) {
    const meses = [
      'janeiro','fevereiro','março','abril','maio','junho',
      'julho','agosto','setembro','outubro','novembro','dezembro'
    ];
    final d = dt.day.toString().padLeft(2, '0');
    final m = meses[dt.month - 1];
    final monthCap = m[0].toUpperCase() + m.substring(1);
    final y = dt.year;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d de $monthCap de $y às $hh:${mm}h';
  }


  // Soma de frutos colhidos por raridade na corrida (a partir das actions "harvest")
  Future<Map<String, int>> _fetchHarvestFruitsByType(String runId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('actions')
        .where('runId', isEqualTo: runId)
        .where('type', isEqualTo: 'harvest');
    if (uid != null) q = q.where('uid', isEqualTo: uid);

    final snap = await q.get();
    final out = {'common': 0, 'rare': 0, 'epic': 0};
    for (final d in snap.docs) {
      final data = d.data();
      final t = (data['plantType'] as String?) ?? 'common';
      final points = (data['points'] is num) ? (data['points'] as num).toInt() : 0;
      final ppf = (data['ppf'] as num?)?.toInt();
      if (ppf != null && ppf > 0) {
        final fruits = points ~/ ppf;
        out[t] = (out[t] ?? 0) + fruits;
      }
    }
    return out;
  }

  // Soma de frutos roubados por raridade na corrida (a partir das actions "steal")
  Future<Map<String, int>> _fetchStolenFruitsByType(String runId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('actions')
        .where('runId', isEqualTo: runId)
        .where('type', isEqualTo: 'steal');
    if (uid != null) q = q.where('uid', isEqualTo: uid);

    final snap = await q.get();
    final out = {'common': 0, 'rare': 0, 'epic': 0};
    for (final d in snap.docs) {
      final data = d.data();
      final t = (data['plantType'] as String?) ?? 'common';
      final points = (data['points'] is num) ? (data['points'] as num).toInt() : 0;
      final ppf = (data['ppf'] as num?)?.toInt();
      if (ppf != null && ppf > 0) {
        final fruits = points ~/ ppf; // normalmente 1 por ação de roubo
        out[t] = (out[t] ?? 0) + fruits;
      }
    }
    return out;
  }

  // Soma de plantios por raridade na corrida (a partir das actions "plant")
  Future<Map<String, int>> _fetchPlantedCountsByType(String runId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('actions')
        .where('runId', isEqualTo: runId)
        .where('type', isEqualTo: 'plant');
    if (uid != null) q = q.where('uid', isEqualTo: uid);

    final snap = await q.get();
    final out = {'common': 0, 'rare': 0, 'epic': 0};
    for (final d in snap.docs) {
      final data = d.data();
      final t = (data['plantType'] as String?) ?? 'common';
      out[t] = (out[t] ?? 0) + 1;
    }
    return out;
  }

  // Soma de regas por raridade na corrida (a partir das actions "water")
  Future<Map<String, int>> _fetchWaterCountsByType(String runId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('actions')
        .where('runId', isEqualTo: runId)
        .where('type', isEqualTo: 'water');
    if (uid != null) q = q.where('uid', isEqualTo: uid);

    final snap = await q.get();
    final out = {'common': 0, 'rare': 0, 'epic': 0};
    for (final d in snap.docs) {
      final data = d.data();
      final t = (data['plantType'] as String?) ?? 'common';
      out[t] = (out[t] ?? 0) + 1;
    }
    return out;
  }

  // Pílula de informação (ícone + texto) para cabeçalho
  Widget _infoPill(IconData icon, String text) {
    return Container
      (
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black87),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }

  // [MOD] Cor por raridade (common=verde, rare=azul, epic=roxo)
  Color _colorForType(String? type) {
    switch (type) {
      case 'epic':
        return Colors.purple;
      case 'rare':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  // [MODIFICADO 2025-08-18] Formata coordenadas curtas
  String _fmtCoord(LatLng? p) {
    if (p == null) return '—';
    String f(double v) => v.toStringAsFixed(5);
    return '${f(p.latitude)}, ${f(p.longitude)}';
  }

  // [MODIFICADO 2025-08-18] ListTile compacto para o card de métricas
  Widget _MetricTile({required IconData icon, required String title, required String value}) {
    return ListTile(
      leading: Icon(icon, size: 20, color: Colors.black87),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
      onTap: null,
    );
  }

  // Bloco compacto de métrica (rótulo + valor)
  Widget _metricCell(BuildContext context, String label, String value, {double bottom = 12}) {
    return Padding(
      padding: EdgeInsets.only(top: 12, bottom: bottom, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );
  }

  // Mini legenda por tipo (plantios/ações) com ícone customizável e modo compacto
  Widget _typeLegend(Map<String, int> counts, {IconData icon = Icons.spa, bool compact = false}) {
    EdgeInsets pad = compact ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2) : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    double gap = compact ? 4 : 6;
    double spacing = compact ? 6 : 8;

    Widget pill(Color c, int n) => Container(
      padding: pad,
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          SizedBox(width: gap),
          Text('$n', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        if ((counts['common'] ?? 0) > 0) pill(Colors.green, counts['common']!),
        if ((counts['rare'] ?? 0) > 0) pill(Colors.blue, counts['rare']!),
        if ((counts['epic'] ?? 0) > 0) pill(Colors.purple, counts['epic']!),
      ],
    );
  }

  // [MODIFICADO 2025-08-18] Linha de ação com insígnias ao lado do título
  Widget _actionLine({required IconData icon, required String title, required Map<String, int> counts}) {
    final total = (counts['common'] ?? 0) + (counts['rare'] ?? 0) + (counts['epic'] ?? 0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Colors.black87),
          const SizedBox(width: 8),
          // Título + badges inline
          Expanded(
            child: Row(
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Flexible(child: _typeLegend(counts, icon: icon, compact: true)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('$total', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // [MODIFICADO 2025-08-18] Card translúcido com blur e borda arredondada (estilo do print)
  Widget _frostCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.54),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.35)),
          ),
          child: child,
        ),
      ),
    );
  }

  // Emoji leading helper (substitui ícones por emojis mantendo alinhamento)
  Widget _emojiLeading(String emoji, {double size = 20}) {
    return SizedBox(
      width: 24,
      child: Center(
        child: Text(
          emoji,
          style: TextStyle(fontSize: size, height: 1.0),
        ),
      ),
    );
  }

  // Badge compacto com IMAGEM da planta por raridade (common/rare/epic)
  Widget _miniBadgePlant(String type, int n) {
    String _assetFor(String t) {
      // ajuste estes caminhos se necessário
      switch (t) {
        case 'epic': return 'assets/plants/epic.png';
        case 'rare': return 'assets/plants/rare.png';
        default:     return 'assets/plants/common.png';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ícone/imagem da planta
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              _assetFor(type),
              width: 16,
              height: 16,
              fit: BoxFit.contain,
              errorBuilder: (ctx, err, stack) => Icon(
                Icons.spa,
                size: 16,
                color: _colorForType(type),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _segmentBar({required int common, required int rare, required int epic}) {
    final total = (common + rare + epic).clamp(1, 1 << 31);
    int flex(int v) => ((v / total) * 1000).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            Expanded(flex: flex(common), child: Container(color: Colors.green.withOpacity(common > 0 ? 0.9 : 0.18))),
            Expanded(flex: flex(rare),   child: Container(color: Colors.blue .withOpacity(rare   > 0 ? 0.9 : 0.18))),
            Expanded(flex: flex(epic),   child: Container(color: Colors.purple.withOpacity(epic   > 0 ? 0.9 : 0.18))),
          ],
        ),
      ),
    );
  }

  Widget _actionStatRowSegmented({
    required String emoji,
    required String title,
    required Map<String, int> counts,
  }) {
    final common = counts['common'] ?? 0;
    final rare   = counts['rare']   ?? 0;
    final epic   = counts['epic']   ?? 0;
    final total  = common + rare + epic;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _emojiLeading(emoji),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))), // [MOD 2025-08-18] igual ao card de métricas
              const SizedBox(width: 8),
              Text('$total', style: const TextStyle(fontWeight: FontWeight.w700)), // [MOD 2025-08-18] igual ao card de métricas
            ],
          ),
          const SizedBox(height: 8),
          _segmentBar(common: common, rare: rare, epic: epic),
          const SizedBox(height: 8),
          Row(
            children: [
              if (common > 0) _miniBadgePlant('common', common),
              if (common > 0 && (rare > 0 || epic > 0)) const SizedBox(width: 6),
              if (rare   > 0) _miniBadgePlant('rare',  rare),
              if (rare   > 0 && epic > 0) const SizedBox(width: 6),
              if (epic   > 0) _miniBadgePlant('epic',  epic),
            ],
          ),
        ],
      ),
    );
  }

  // Linha "Colhidas" mostrando total de plantas e, entre parênteses, total de FRUTOS
  Widget _harvestRowWithFruits({
    required Map<String, int> plantCounts,
    required Map<String, int> fruitCounts,
  }) {
    final pc = plantCounts['common'] ?? 0;
    final pr = plantCounts['rare'] ?? 0;
    final pe = plantCounts['epic'] ?? 0;
    final plantsTotal = pc + pr + pe;

    final fc = fruitCounts['common'] ?? 0;
    final fr = fruitCounts['rare'] ?? 0;
    final fe = fruitCounts['epic'] ?? 0;
    final fruitsTotal = fc + fr + fe;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _emojiLeading('🍒'),
              const SizedBox(width: 8),
              const Expanded(child: Text('Colhidas', style: TextStyle(fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Text('$plantsTotal ($fruitsTotal 🍒)', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          _segmentBar(common: pc, rare: pr, epic: pe),
          const SizedBox(height: 8),
          Row(
            children: [
              if (pc > 0) _miniBadgePlant('common', pc),
              if (pc > 0 && (pr > 0 || pe > 0)) const SizedBox(width: 6),
              if (pr > 0) _miniBadgePlant('rare', pr),
              if (pr > 0 && pe > 0) const SizedBox(width: 6),
              if (pe > 0) _miniBadgePlant('epic', pe),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final km = distanceMeters / 1000.0;

    // Altura responsiva para o header do mapa
    final screenH = MediaQuery.of(context).size.height;
    final double mapMax = (screenH * 0.45).clamp(340.0, 520.0);
    final double mapMin = (screenH * 0.22).clamp(150.0, 240.0);

    // [MOD] Lê argumentos passados pela RunHistoryPage (plantedWithType)
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    List<Map<String, dynamic>> plantedWithType = [];
    if (routeArgs is Map && routeArgs['plantedWithType'] is List) {
      final raw = routeArgs['plantedWithType'] as List;
      for (final item in raw) {
        if (item is Map) {
          final lat = (item['lat'] as num?)?.toDouble();
          final lng = (item['lng'] as num?)?.toDouble();
          final type = item['type'] as String? ?? 'common';
          if (lat != null && lng != null) {
            plantedWithType.add({'lat': lat, 'lng': lng, 'type': type});
          }
        }
      }
    }

    // [MOD] Rega, roubo e colheita — pontos e contagem por tipo
    List<LatLng> waterPoints = [];
    final Map<String, int> waterTypeCounts = {'common': 0, 'rare': 0, 'epic': 0};
    if (routeArgs is Map && routeArgs['waterPoints'] is List) {
      final raw = routeArgs['waterPoints'] as List;
      for (final item in raw) {
        if (item is Map) {
          final lat = (item['lat'] as num?)?.toDouble();
          final lng = (item['lng'] as num?)?.toDouble();
          final t = (item['type'] as String?) ?? 'common';
          if (lat != null && lng != null) {
            waterPoints.add(LatLng(lat, lng));
            if (waterTypeCounts.containsKey(t)) {
              waterTypeCounts[t] = (waterTypeCounts[t] ?? 0) + 1;
            }
          }
        }
      }
    }

    List<LatLng> stealPoints = [];
    final Map<String, int> stealTypeCounts = {'common': 0, 'rare': 0, 'epic': 0};
    if (routeArgs is Map && routeArgs['stealPoints'] is List) {
      final raw = routeArgs['stealPoints'] as List;
      for (final item in raw) {
        if (item is Map) {
          final lat = (item['lat'] as num?)?.toDouble();
          final lng = (item['lng'] as num?)?.toDouble();
          final t = (item['type'] as String?) ?? 'common';
          if (lat != null && lng != null) {
            stealPoints.add(LatLng(lat, lng));
            if (stealTypeCounts.containsKey(t)) {
              stealTypeCounts[t] = (stealTypeCounts[t] ?? 0) + 1;
            }
          }
        }
      }
    }

    List<LatLng> harvestPoints = [];
    final Map<String, int> harvestTypeCounts = {'common': 0, 'rare': 0, 'epic': 0};
    if (routeArgs is Map && routeArgs['harvestPoints'] is List) {
      final raw = routeArgs['harvestPoints'] as List;
      for (final item in raw) {
        if (item is Map) {
          final lat = (item['lat'] as num?)?.toDouble();
          final lng = (item['lng'] as num?)?.toDouble();
          final t = (item['type'] as String?) ?? 'common';
          if (lat != null && lng != null) {
            harvestPoints.add(LatLng(lat, lng));
            if (harvestTypeCounts.containsKey(t)) {
              harvestTypeCounts[t] = (harvestTypeCounts[t] ?? 0) + 1;
            }
          }
        }
      }
    }

    // [MOD] Preparar pontos para enquadrar o mapa (path + plantas + water/steal/harvest)
    final List<LatLng> allPoints = [
      ...path,
      for (final m in plantedWithType)
        LatLng((m['lat'] as double), (m['lng'] as double)),
      ...waterPoints,
      ...stealPoints,
      ...harvestPoints,
    ];
    LatLng? _center;
    LatLngBounds? _bounds;
    if (allPoints.isNotEmpty) {
      if (allPoints.length == 1) {
        _center = allPoints.first;
      } else {
        _bounds = LatLngBounds.fromPoints(allPoints);
      }
    }

    // [MOD] Contagem por tipo (apenas plantios têm tipo denormalizado aqui)
    final Map<String, int> plantedTypeCounts = {
      'common': 0,
      'rare': 0,
      'epic': 0,
    };
    for (final m in plantedWithType) {
      final t = (m['type'] as String?) ?? 'common';
      if (plantedTypeCounts.containsKey(t)) {
        plantedTypeCounts[t] = (plantedTypeCounts[t] ?? 0) + 1;
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          // [MODIFICADO 2025-08-18] Fundo de página com imagem de mapa
          Positioned.fill(
            child: Image.asset(
              'assets/summary.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // [MODIFICADO] Gradiente branco topo e base, transparente no meio (como nas outras telas)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.8),
                    Colors.white.withOpacity(0.0),
                    Colors.white.withOpacity(0.8),
                  ],
                  stops: const [0.0, 1.0, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            top: true,
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20), // [MODIFICADO 2025-08-18] Aproxima o botão voltar da borda esquerda
              children: [
                // [MODIFICADO 2025-08-18] Botão voltar no topo
                Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: const Offset(-8, 0), // [MODIFICADO 2025-08-18] aproxima a seta da borda esquerda
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.chevron_left, color: Colors.black, size: 32),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // [MODIFICADO 2025-08-18] Cabeçalho alinhado ao print (peso/itálico/tamanho)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Text(
                    'Trajeto',
                    style: const TextStyle(
                      fontSize: 28, // próximo ao exemplo "Morning Run"
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.2,
                      color: Colors.black,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

                // [MODIFICADO 2025-08-18] Distância em destaque com "km" em itálico
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: (distanceMeters / 1000.0).toStringAsFixed(2).replaceAll('.', ','),
                          style: const TextStyle(
                            fontSize: 68,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            letterSpacing: -1.0,
                            color: Colors.black,
                            fontStyle: FontStyle.italic, // [MODIFICADO 2025-08-18] Números em itálico como no exemplo
                          ),
                        ),
                        TextSpan(
                          text: ' km',
                          style: const TextStyle(
                            fontSize: 44, // ligeiramente menor
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic, // itálico como no print
                            letterSpacing: -0.5,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // ROTA + coordenadas (início / fim) ao lado do traçado
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Esquerda: título ROTA e coordenadas
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.directions_run, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'ROTA',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  fontStyle: FontStyle.italic, // itálico
                                  letterSpacing: 0.6,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.my_location, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _fmtCoord(path.isNotEmpty ? path.first : null),
                                  style: const TextStyle(fontWeight: FontWeight.w700), // [MODIFICADO 2025-08-18] Coordenadas em negrito
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.flag, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _fmtCoord(path.isNotEmpty ? path.last : null),
                                  style: const TextStyle(fontWeight: FontWeight.w700), // [MODIFICADO 2025-08-18] Coordenadas em negrito
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Direita: mini traçado
                    // [MODIFICADO 2025-08-18] Sketch sem fundo, apenas o traçado
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: Transform.translate(
                        offset: const Offset(0, -20), // [MODIFICADO 2025-08-18] desloca o traçado um pouco para cima
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: _RouteSketch(points: path),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 0),

                // [MODIFICADO 2025-08-18] Card de métricas com dados reais (Pontuação, Distância, Pace, Duração)
                FutureBuilder<int>(
                  future: runId != null ? _getScorePreferDenorm(runId!) : Future.value(0),
                  builder: (context, snap) {
                    final pts = snap.data ?? 0;
                    return _frostCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            ListTile(
                              leading: _emojiLeading('🏆'),
                              // [MODIFICADO 2025-08-18] Igual ao card de ações (título: w600, mesmo tamanho e cor)
                              title: const Text(
                                'Pontuação',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              // [MODIFICADO 2025-08-18] Igual ao card de ações (valor: w700, mesmo tamanho e cor)
                              trailing: Text(
                                '$pts',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                              visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            ListTile(
                              leading: _emojiLeading('📍'),
                              // [MODIFICADO 2025-08-18] Igual ao card de ações (título: w600, mesmo tamanho e cor)
                              title: const Text(
                                'Distância',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              // [MODIFICADO 2025-08-18] Igual ao card de ações (valor: w700, mesmo tamanho e cor)
                              trailing: Text(
                                '${(distanceMeters / 1000).toStringAsFixed(2)} km',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                              visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            ListTile(
                              leading: _emojiLeading('⚡️'),
                              // [MODIFICADO 2025-08-18] Igual ao card de ações (título: w600, mesmo tamanho e cor)
                              title: const Text(
                                'Pace',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              // [MODIFICADO 2025-08-18] Igual ao card de ações (valor: w700, mesmo tamanho e cor)
                              trailing: Text(
                                _fmtPace(distanceMeters, durationMs),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                              visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            ListTile(
                              leading: _emojiLeading('⏱️'),
                              // [MODIFICADO 2025-08-18] Igual ao card de ações (título: w600, mesmo tamanho e cor)
                              title: const Text(
                                'Duração',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              // [MODIFICADO 2025-08-18] Igual ao card de ações (valor: w700, mesmo tamanho e cor)
                              trailing: Text(
                                _fmtDuration(durationMs),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                              visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),
                // [MODIFICADO 2025-08-18] Card com ações do jogo e insígnias por tipo (frosted)
                _frostCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _actionStatRowSegmented(emoji: '🌱', title: 'Plantadas', counts: plantedTypeCounts),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _actionStatRowSegmented(emoji: '💧', title: 'Regadas',   counts: waterTypeCounts),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _actionStatRowSegmented(emoji: '🥷🏼️', title: 'Roubadas',  counts: stealTypeCounts),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        FutureBuilder<Map<String, int>>(
                          future: runId != null
                              ? _fetchHarvestFruitsByType(runId!)
                              : Future.value(const {'common': 0, 'rare': 0, 'epic': 0}),
                          builder: (context, snap) {
                            final fruits = snap.data ?? const {'common': 0, 'rare': 0, 'epic': 0};
                            return _harvestRowWithFruits(
                              plantCounts: harvestTypeCounts,
                              fruitCounts: fruits,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Botão "Share Your Run" (sem ação por enquanto)
                // GestureDetector(
                //   onTap: null,
                //   child: Container(
                //     height: 54,
                //     alignment: Alignment.center,
                //     decoration: BoxDecoration(
                //       color: const Color(0xFFE6FF2E), // amarelo/verde vivo
                //       borderRadius: BorderRadius.circular(16),
                //     ),
                //     child: Row(
                //       mainAxisAlignment: MainAxisAlignment.center,
                //       children: const [
                //         Text('Share Your Run', style: TextStyle(fontWeight: FontWeight.w700)),
                //         SizedBox(width: 10),
                //         CircleAvatar(
                //           radius: 12,
                //           backgroundColor: Colors.black,
                //           child: Icon(Icons.north_east, size: 14, color: Colors.white),
                //         ),
                //       ],
                //     ),
                //   ),
                // ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteSketch extends StatelessWidget {
  final List<LatLng> points;
  const _RouteSketch({required this.points});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RouteSketchPainter(points),
    );
  }
}

class _RouteSketchPainter extends CustomPainter {
  final List<LatLng> pts;
  _RouteSketchPainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;

    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    Offset toPx(LatLng ll) {
      final x = (lngSpan == 0 ? 0.5 : (ll.longitude - minLng) / (lngSpan)) * w + pad;
      final y = h - (latSpan == 0 ? 0.5 : (ll.latitude - minLat) / (latSpan)) * h + pad;
      return Offset(x, y);
    }

    final ui.Path path = ui.Path();
    for (int i = 0; i < pts.length; i++) {
      final o = toPx(pts[i]);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }

    final paintStroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paintStroke);

    final start = toPx(pts.first);
    final end = toPx(pts.last);
    final dotPaint = Paint()..color = Colors.black;
    canvas.drawCircle(start, 4, dotPaint);
    canvas.drawCircle(end, 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RouteSketchPainter oldDelegate) => oldDelegate.pts != pts;
}

class _MapHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget Function(BuildContext context, double shrinkOffset, bool overlapsContent) builder;

  _MapHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.builder,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: builder(context, shrinkOffset, overlapsContent));
  }

  @override
  bool shouldRebuild(covariant _MapHeaderDelegate oldDelegate) {
    return minHeight != oldDelegate.minHeight || maxHeight != oldDelegate.maxHeight;
  }
}