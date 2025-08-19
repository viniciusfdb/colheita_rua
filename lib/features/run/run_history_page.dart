import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

import 'run_summary_page.dart';

class RunHistoryPage extends StatefulWidget {
  const RunHistoryPage({super.key});
  @override
  State<RunHistoryPage> createState() => _RunHistoryPageState();
}

class _RunHistoryPageState extends State<RunHistoryPage> {
  int _loadedCount = 4; // inicia com 4 itens visíveis

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8F7),
        body: SafeArea(
          child: Center(child: Text('Faça login para ver seu histórico.')),
        ),
      );
    }

    final runsQuery = FirebaseFirestore.instance
        .collection('runs')
        .where('uid', isEqualTo: uid);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/history.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Overlay gradient for readability
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
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // Main content
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: runsQuery.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Erro ao carregar: ${snap.error}'));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const Center(child: Text('Nenhuma corrida encontrada.'));
              }

              final docs = snap.data!.docs;
              docs.sort((a, b) {
                final sa = _toDateTime(a['startedAt']);
                final sb = _toDateTime(b['startedAt']);
                return sb.compareTo(sa);
              });
              final int displayCount = (_loadedCount < docs.length) ? _loadedCount : docs.length;
              return SafeArea(
                top: true,
                bottom: true,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Transform.translate(
                                    offset: const Offset(-8, 0), // aproxima a seta da borda esquerda
                                    child: IconButton(
                                      onPressed: () {
                                        final nav = Navigator.of(context);
                                        if (nav.canPop()) nav.pop();
                                      },
                                      icon: const Icon(Icons.chevron_left, color: Colors.black, size: 32),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            RichText(
                              text: TextSpan(
                                text: 'Histórico de Trajetos',
                                style: const TextStyle(
                                  fontSize: 45,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: -0.5,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.21,
                      ),
                    ),
                    SliverList.separated(
                      itemCount: displayCount,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();

                        final distance = (data['distanceMeters'] as num?)?.toDouble() ?? 0.0;
                        final dm = data['durationMs'];
                        final durationMs = dm is int ? dm : (dm is num ? dm.toInt() : 0);
                        final startedAtTs = data['startedAt'];
                        final endedAtTs = data['endedAt'];
                        final pc = data['plantedCount'];
                        final plantedCount = pc is int ? pc : (pc is num ? pc.toInt() : 0);

                        final wc = data['wateredCount'];
                        final wateredCount = wc is int ? wc : (wc is num ? wc.toInt() : 0);
                        final sc = data['stolenCount'];
                        final stolenCount = sc is int ? sc : (sc is num ? sc.toInt() : 0);
                        final hc = data['harvestedCount'];
                        final harvestedCount = hc is int ? hc : (hc is num ? hc.toInt() : 0);

                        final startedAt = _toDateTime(startedAtTs);
                        final endedAt = _toDateTime(endedAtTs);

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minLeadingWidth: 0,
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFFE6FF2E),
                                    child: Icon(Icons.directions_run, color: Colors.black),
                                  ),
                                  title: Text(
                                    '${(distance / 1000).toStringAsFixed(2)} km',
                                    style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                                  ),
                                  subtitle: Text(
                                    DateFormat('dd/MM/yyyy').format(startedAt),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                  trailing: Builder(
                                    builder: (context) {
                                      final tp = data['totalPoints'];
                                      final int? val = tp is num ? tp.toInt() : null;
                                      final paceStr = _fmtPace(durationMs, distance);
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Color(0xFFE6FF2E),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              paceStr,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Icon(Icons.emoji_events, color: Colors.amber),
                                          const SizedBox(width: 4),
                                          Text(
                                            val == null ? '--' : '$val pts',
                                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  onTap: () async {
                                    // (mantém a lógica existente do onTap)
                                    final runSnap = await FirebaseFirestore.instance
                                        .collection('runs')
                                        .doc(doc.id)
                                        .get();
                                    final runData = runSnap.data() ?? {};

                                    final List<dynamic> rawPath = (runData['path'] ?? []) as List<dynamic>;
                                    final List<LatLng> path = rawPath
                                        .whereType<Map<String, dynamic>>()
                                        .map((m) => LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()))
                                        .toList(growable: false);

                                    List<Map<String, dynamic>> plantedWithType = [];
                                    if (runData['plantedWithType'] is List) {
                                      final raw = runData['plantedWithType'] as List;
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

                                    List<LatLng> plantedPoints = [];
                                    if (runData['plantedPoints'] is List) {
                                      final raw = runData['plantedPoints'] as List;
                                      for (final item in raw) {
                                        if (item is Map) {
                                          final lat = (item['lat'] as num?)?.toDouble();
                                          final lng = (item['lng'] as num?)?.toDouble();
                                          if (lat != null && lng != null) {
                                            plantedPoints.add(LatLng(lat, lng));
                                          }
                                        }
                                      }
                                    }

                                    if (plantedPoints.isEmpty) {
                                      final List<dynamic> rawPlantedIds = (runData['plantedIds'] ?? []) as List<dynamic>;
                                      final List<String> plantedIds = rawPlantedIds.whereType<String>().toList();
                                      if (plantedIds.isNotEmpty) {
                                        final db = FirebaseFirestore.instance;
                                        final accPoints = <LatLng>[];
                                        final accWithType = <Map<String, dynamic>>[];
                                        for (var i = 0; i < plantedIds.length; i += 10) {
                                          final chunk = plantedIds.sublist(i, (i + 10 > plantedIds.length) ? plantedIds.length : i + 10);
                                          final plantsSnap = await db
                                              .collection('plants')
                                              .where(FieldPath.documentId, whereIn: chunk)
                                              .get();
                                          for (final d in plantsSnap.docs) {
                                            final pd = d.data();
                                            final lat = (pd['lat'] as num?)?.toDouble();
                                            final lng = (pd['lng'] as num?)?.toDouble();
                                            if (lat != null && lng != null) {
                                              accPoints.add(LatLng(lat, lng));
                                              accWithType.add({
                                                'lat': lat,
                                                'lng': lng,
                                                'type': (pd['type'] as String?) ?? 'common',
                                              });
                                            }
                                          }
                                        }
                                        plantedPoints = accPoints;
                                        if (plantedWithType.isEmpty) {
                                          plantedWithType = accWithType;
                                        }
                                      }
                                    }

                                    final List<Map<String, dynamic>> waterPoints = [];
                                    if (runData['waterPoints'] is List) {
                                      final raw = runData['waterPoints'] as List;
                                      for (final item in raw) {
                                        if (item is Map) {
                                          final lat = (item['lat'] as num?)?.toDouble();
                                          final lng = (item['lng'] as num?)?.toDouble();
                                          if (lat != null && lng != null) {
                                            waterPoints.add({'lat': lat, 'lng': lng});
                                          }
                                        }
                                      }
                                    }
                                    final List<Map<String, dynamic>> stealPoints = [];
                                    if (runData['stealPoints'] is List) {
                                      final raw = runData['stealPoints'] as List;
                                      for (final item in raw) {
                                        if (item is Map) {
                                          final lat = (item['lat'] as num?)?.toDouble();
                                          final lng = (item['lng'] as num?)?.toDouble();
                                          if (lat != null && lng != null) {
                                            stealPoints.add({'lat': lat, 'lng': lng});
                                          }
                                        }
                                      }
                                    }

                                    final startedAt2 = _toDateTime(runData['startedAt']);
                                    final endedAt2 = _toDateTime(runData['endedAt']);
                                    final dm2 = runData['durationMs'];
                                    final durationMs2 = dm2 is int ? dm2 : (dm2 is num ? dm2.toInt() : 0);
                                    final distance2 = (runData['distanceMeters'] as num?)?.toDouble() ?? 0.0;
                                    final pc2 = runData['plantedCount'];
                                    final plantedCount2 = pc2 is int ? pc2 : (pc2 is num ? pc2.toInt() : 0);

                                    final wc2 = runData['wateredCount'];
                                    final wateredCount2 = wc2 is int ? wc2 : (wc2 is num ? wc2.toInt() : 0);
                                    final sc2 = runData['stolenCount'];
                                    final stolenCount2 = sc2 is int ? sc2 : (sc2 is num ? sc2.toInt() : 0);
                                    final hc2 = runData['harvestedCount'];
                                    final harvestedCount2 = hc2 is int ? hc2 : (hc2 is num ? hc2.toInt() : 0);

                                    if (!context.mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        settings: RouteSettings(arguments: {
                                          'plantedWithType': plantedWithType,
                                          'waterPoints': waterPoints,
                                          'stealPoints': stealPoints,
                                        }),
                                        builder: (_) => RunSummaryPage(
                                          runId: doc.id,
                                          distanceMeters: distance2,
                                          durationMs: durationMs2,
                                          plantedCount: plantedCount2,
                                          plantedPoints: plantedPoints,
                                          path: path,
                                          startedAt: startedAt2,
                                          endedAt: endedAt2,
                                          wateredCount: wateredCount2,
                                          stolenCount: stolenCount2,
                                          harvestedCount: harvestedCount2,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (displayCount < docs.length)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Center(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _loadedCount = (_loadedCount + 5).clamp(0, docs.length);
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black87,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Ver mais'),
                            ),
                          ),
                        ),
                      )
                    else
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

DateTime _toDateTime(dynamic ts) {
  if (ts is Timestamp) return ts.toDate();
  if (ts is DateTime) return ts;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

String _fmtKm(double meters) => '${(meters / 1000).toStringAsFixed(2)} km';

String _fmtDuration(int ms) {
  final s = (ms ~/ 1000) % 60;
  final m = (ms ~/ 60000) % 60;
  final h = (ms ~/ 3600000);
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String _fmtPace(int durationMs, double meters) {
  if (meters <= 0) return '--/km';
  final secondsTotal = (durationMs / 1000).floor();
  final paceSecPerKm = (secondsTotal / (meters / 1000)).round();
  final m = paceSecPerKm ~/ 60;
  final s = paceSecPerKm % 60;
  return '$m:${s.toString().padLeft(2, '0')}/km';
  }

String _fmtDate(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}