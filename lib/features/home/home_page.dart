import 'package:flutter/material.dart';
import 'dart:ui';
import '../map/map_page.dart';
import '../profile/profile_page.dart';

import '../run/run_history_page.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      extendBody: true,
      // Sem AppBar — usamos um topo clean com botão de sair flutuante
      body: Stack(
        children: [
          // Fundo com imagem cobrindo toda a Home
          Positioned.fill(
            child: Image.asset(
              'assets/home.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Gradient overlay (white top and bottom, transparent middle)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.4),
                    Colors.white.withOpacity(0.9),
                    Colors.white.withOpacity(0.6),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // [MODIFICADO 2025-08-18] Reordenação da hierarquia: mapa em cima, eventos e demais cards abaixo do mapa.

                // Saudação estilo "Hi + Nome"
                const _HeaderGreeting(),
                const SizedBox(height: 24), // [MODIFICADO 2025-08-18] Espaçamento unificado entre cabeçalho e mapa

                // [MODIFICADO 2025-08-18] Mapa movido para o topo
                _HeroMapCard(
                  onOpenMap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage())),
                ),
                const SizedBox(height: 24),
                // Seção dinâmica: Hoje (se última atividade for hoje) ou Histórico
                const _LastActivitySection(),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 0),
                  child: Text(
                    'Próximos Eventos',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 8),
                const _EventsCarousel(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.5))),
            ),
            child: BottomNavigationBar(
              backgroundColor: Colors.transparent,
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              selectedItemColor: Colors.black,
              unselectedItemColor: Colors.black,
              selectedIconTheme: const IconThemeData(color: Colors.black),
              unselectedIconTheme: const IconThemeData(color: Colors.black),
              selectedLabelStyle: const TextStyle(color: Colors.black, height: 1.2),
              unselectedLabelStyle: const TextStyle(color: Colors.black, height: 1.2),
              showUnselectedLabels: true,
              currentIndex: 0,
              onTap: (i) {
                if (i == 1) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
                }
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.home),
                  ),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.person),
                  ),
                  label: 'Perfil',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderGreeting extends StatelessWidget {
  const _HeaderGreeting();

  String _firstName() {
    final u = FirebaseAuth.instance.currentUser;
    final dn = u?.displayName?.trim();
    if (dn != null && dn.isNotEmpty) {
      return dn.split(' ').first;
    }
    final email = u?.email ?? '';
    if (email.contains('@')) return email.split('@').first;
    return 'Jogador';
  }

  @override
  Widget build(BuildContext context) {
    final hi = 'Olá, ${_firstName()}! 👋';
    final msg = 'Pronto para um trajeto mais verde? 🌿';
    return Padding(
      padding: const EdgeInsets.only(left: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE6FF2E),
            child: Text(
              _firstName().isNotEmpty ? _firstName()[0].toUpperCase() : 'J',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hi,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, height: 1.0),
              ),
              const SizedBox(height: 2),
              Text(
                msg,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventsCarousel extends StatelessWidget {
  const _EventsCarousel({super.key});

  // Dados mockados por enquanto; no futuro virão dos eventos do app
  List<Map<String, String>> get _items => const [
        {
          'title': '',
          'subtitle': '',
          'image': 'https://images.unsplash.com/photo-1492496913980-501348b61469?auto=format&fit=crop&w=1200&q=60',
        },
        {
          'title': '',
          'subtitle': '',
          'image': 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=1200&q=60', // [MODIFICADO 2025-08-18] Substituída imagem quebrada do card "Rota Verde"
        },
        {
          'title': '',
          'subtitle': '',
          'image': 'https://images.unsplash.com/photo-1501004318641-b39e6451bec6?auto=format&fit=crop&w=1200&q=60',
        },
      ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cardW = width * 0.80; // proporção parecida com o exemplo
    const cardH = 180.0;

    return SizedBox(
      height: cardH,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final it = _items[i];
          return _EventCard(
            width: cardW,
            height: cardH,
            title: it['title'] ?? '',
            subtitle: it['subtitle'] ?? '',
            imageUrl: it['image'],
            onTap: () {},
          );
        },
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final double width;
  final double height;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback onTap;
  const _EventCard({
    super.key,
    required this.width,
    required this.height,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 1,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Fundo com imagem; se falhar, usa um degradê discreto
              if (imageUrl != null)
                Image.network(imageUrl!, fit: BoxFit.cover)
              else
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFe9ecef), Color(0xFFdee2e6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              // leve rounded interno do exemplo
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              // [NOVO] Overlay blur com texto central
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Center(
                    child: Text(
                      'Em desenvolvimento',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              // Texto sobreposto, alinhado ao canto inferior esquerdo
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withOpacity(0.95),
                              fontWeight: FontWeight.w400,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroMapCard extends StatefulWidget {
  final VoidCallback onOpenMap;
  const _HeroMapCard({required this.onOpenMap});
  @override
  State<_HeroMapCard> createState() => _HeroMapCardState();
}

class _HeroMapCardState extends State<_HeroMapCard> {
  LatLng? _center;
  String _status = 'Carregando mapa…';

  @override
  void initState() {
    super.initState();
    _loadCenter();
  }

  Future<void> _loadCenter() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _status = 'GPS desativado');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        setState(() => _status = 'Permissão negada');
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() => _status = 'Permissão negada permanentemente');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _center = LatLng(pos.latitude, pos.longitude);
        _status = 'ok';
      });
    } catch (_) {
      setState(() => _status = 'Erro ao obter localização');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onOpenMap,
      child: Card(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 160,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_center == null)
                Center(child: Text(_status, style: Theme.of(context).textTheme.bodyMedium))
              else
                FlutterMap(
                  options: MapOptions(
                    initialCenter: _center!,
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.colheita_rua',
                    ),
                  ],
                ),
              // [MODIFICADO 2025-08-18] Overlay cinza uniforme por toda a área do mapa
              if (_center != null)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.05), // cinza suave por toda a área
                  ),
                ),
              // CTA em pílula branca
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.black12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '  Vamos plantar!  ',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.black,
                                fontWeight: FontWeight.w400,
                              ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE6FF2E),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.north_east, color: Colors.black, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LastActivitySection extends StatefulWidget {
  const _LastActivitySection();
  @override
  State<_LastActivitySection> createState() => _LastActivitySectionState();
}

class _LastActivitySectionState extends State<_LastActivitySection> {
  late Future<Map<String, dynamic>?> _future; // [MODIFICADO 2025-08-18] Memoização do fetch para evitar flicker

  @override
  void initState() {
    super.initState();
    _future = _fetchLastRun();
  }

  Future<Map<String, dynamic>?> _fetchLastRun() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    // 1) Tenta com orderBy(endedAt) (mais correto)
    try {
      final snap = await FirebaseFirestore.instance
          .collection('runs')
          .where('uid', isEqualTo: uid)
          .orderBy('endedAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
    } on FirebaseException catch (e) {
      // 2) Se exigir índice ou outro erro de pré-condição, cai para o fallback sem orderBy
      if (e.code != 'failed-precondition') {
        // outros erros, tenta mesmo assim o fallback
      }
    }
    // Fallback: busca alguns e escolhe o mais recente no cliente
    final fb = await FirebaseFirestore.instance
        .collection('runs')
        .where('uid', isEqualTo: uid)
        .limit(20)
        .get();
    if (fb.docs.isEmpty) return null;
    Map<String, dynamic>? best;
    DateTime bestTime = DateTime.fromMillisecondsSinceEpoch(0);
    for (final d in fb.docs) {
      final data = d.data();
      DateTime? t;
      final ea = data['endedAt'];
      if (ea is Timestamp) t = ea.toDate();
      final sa = data['startAt'] ?? data['startedAt'] ?? data['createdAt'];
      if (t == null && sa is Timestamp) t = sa.toDate();
      t ??= DateTime.fromMillisecondsSinceEpoch(0);
      if (t.isAfter(bestTime)) {
        bestTime = t;
        best = data;
      }
    }
    return best;
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _formatDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
  double _toKm(num? distanceKm, num? distanceMeters, num? distanceGeneric) {
    if (distanceKm != null) return distanceKm.toDouble();
    if (distanceMeters != null) return distanceMeters.toDouble() / 1000.0;
    if (distanceGeneric != null) {
      final v = distanceGeneric.toDouble();
      // Heurística: se for muito grande, trata como metros
      return v > 50 ? v / 1000.0 : v;
    }
    return 0.0;
  }
  String? _formatPace(int? sec, double? km, {String? givenPace}) {
    if (givenPace != null && givenPace.isNotEmpty) return givenPace;
    if (sec == null || km == null || km <= 0) return null;
    final paceSec = (sec / km).round();
    final m = (paceSec ~/ 60).toString().padLeft(2, '0');
    final s = (paceSec % 60).toString().padLeft(2, '0');
    return '$m:$s/km';
  }

  // Converte duração vária (ms, s, "mm:ss", "hh:mm:ss") para segundos
  int? _parseDurationToSeconds(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      final n = v.toDouble();
      // Heurística: valores grandes são milissegundos
      if (n >= 10 * 60 * 1000) { // >=10min em ms
        return (n / 1000).round();
      }
      if (n > 3600) {
        // pode ser ms para valores menores de 10min
        if (n > 1000) return (n / 1000).round();
      }
      return n.round();
    }
    if (v is String) {
      final parts = v.split(':').map((e) => e.trim()).toList();
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        return m * 60 + s;
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = int.tryParse(parts[2]) ?? 0;
        return h * 3600 + m * 60 + s;
      }
    }
    return null;
  }

  // Normaliza pace vindo como String ("mm:ss/km"), segundos por km (num) ou ms/km (num grande)
  String? _normalizePace(dynamic v) {
    if (v == null) return null;
    if (v is String && v.trim().isNotEmpty) return v;
    if (v is num) {
      var secPerKm = v.toDouble();
      // Se vier em ms/km, converte
      if (secPerKm > 600) { // >10min em segundos? provavelmente ms
        secPerKm = secPerKm / 1000.0;
      }
      final total = secPerKm.round();
      final m = (total ~/ 60).toString().padLeft(2, '0');
      final s = (total % 60).toString().padLeft(2, '0');
      return '$m:$s/km';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future, // [MODIFICADO 2025-08-18] Usa future memoizada para evitar reconstrução/hot reload
      builder: (context, snap) {
        final data = snap.data;
        // Declare variables to be reused
        double distKm = 0.0;
        num? durationSec;
        String? paceGiven;
        String sectionTitle = 'Última Atividade';
        String subtitle = 'Ver suas atividades';
        num pts = 0; // [MODIFICADO 2025-08-18] Inicialização
        if (data != null) {
          // usa endedAt; fallback para startAt/createdAt
          DateTime? ended;
          final ts = data['endedAt'];
          if (ts is Timestamp) ended = ts.toDate();
          DateTime? refTime = ended;
          if (refTime == null) {
            final sa = data['startAt'] ?? data['startedAt'] ?? data['createdAt'];
            if (sa is Timestamp) refTime = sa.toDate();
          }
          if (refTime != null && _isToday(refTime)) {
            sectionTitle = 'Hoje';
          }
          // --- Monta subtítulo com duração • km • pace ---
          final rawDuration = (data['durationSec'] ??
              data['duration_seconds'] ??
              data['durationMs'] ??
              data['duration_ms'] ??
              data['duration'] ??
              data['seconds']);
          durationSec = _parseDurationToSeconds(rawDuration);
          distKm = _toKm(
            data['distanceKm'] as num?,
            data['distanceMeters'] as num?,
            data['distance'] as num?,
          );
          final rawPace = (data['pace'] ??
              data['paceSecPerKm'] ??
              data['pace_seconds_per_km'] ??
              data['paceMsPerKm'] ??
              data['pace_ms_per_km']);
          paceGiven = _normalizePace(rawPace);
          final parts = <String>[];
          if (durationSec != null) {
            parts.add(_formatDuration(durationSec!.toInt()));
          }
          if (distKm > 0) {
            parts.add('${distKm.toStringAsFixed(2)} km');
          }
          final paceStr = _formatPace(durationSec?.toInt(), distKm, givenPace: paceGiven);
          if (paceStr != null) {
            parts.add(paceStr);
          }
          if (parts.isNotEmpty) {
            subtitle = parts.join(' • ');
          } else {
            subtitle = 'Ver suas atividades';
          }
          pts = (data['totalPoints'] ?? data['score'] ?? 0) as num; // [MODIFICADO 2025-08-18] Pontuação para o card
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 0),
              child: Text(
                sectionTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 8),
            if (snap.connectionState == ConnectionState.waiting) ...[
              const SizedBox.shrink(), // [MODIFICADO 2025-08-18] Evita flicker durante hot reload/carregamento
            ] else if (data != null) ...[
              _AppleStyleActivityCard(
                // Métricas do topo
                metricLeftLabel: 'Distância (km)',
                metricLeftValue: distKm.toStringAsFixed(2),
                metricRightLabel: 'Pace',
                metricRightValue: (paceGiven ?? _formatPace(durationSec?.toInt(), distKm)) ?? '—',

                // Linha de atividade
                activityIcon: Icons.directions_run,
                activityColor: const Color(0xFFE6FF2E),
                activityTitle: 'Atividade',
                activitySubtitle: [
                  if (durationSec != null) _formatDuration(durationSec!.toInt()),
                  '${pts.toString()} pts 🏆',

                ].join(' • '), // Mantém duração + pontuação

                // Rodapé estilo “+ ver histórico”
                footerLabel: 'Ver mais +',
                onOpenDetails: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RunHistoryPage()),
                ),
                onOpenHistory: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RunHistoryPage()),
                ),
              ),
            ] else ...[
              _ActionCard(
                icon: Icons.timer_outlined,
                title: 'Última atividade',
                subtitle: subtitle,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RunHistoryPage())),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.green.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsSummaryCard extends StatelessWidget {
  final num distanceKm;
  final num points;
  final String? pace;       // ex: "05:30/km"
  final String? durationLabel; // ex: "00:33"
  final VoidCallback onTap;
  const _StatsSummaryCard({
    required this.distanceKm,
    required this.points,
    required this.onTap,
    this.pace,
    this.durationLabel,
  });

  Widget _metric(BuildContext context, String label, String value) {
    final labStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54);
    final valStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labStyle),
        const SizedBox(height: 2),
        Text(value, style: valStyle),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final distStr = distanceKm > 0 ? distanceKm.toStringAsFixed(2) : '0.00';
    final paceStr = pace ?? '—';
    final durStr = durationLabel ?? '—';
    final ptsStr = points.toString();

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Primeira linha: Distância | Pontuação
              Row(
                children: [
                  Expanded(child: _metric(context, 'Distância (km)', distStr)),
                  Container(width: 1, height: 28, color: Colors.black12),
                  const SizedBox(width: 12),
                  Expanded(child: _metric(context, 'Pontuação', ptsStr)),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: Colors.black12),
              const SizedBox(height: 12),
              // Segunda linha: Pace | Duração
              Row(
                children: [
                  Expanded(child: _metric(context, 'Pace', paceStr)),
                  Container(width: 1, height: 28, color: Colors.black12),
                  const SizedBox(width: 12),
                  Expanded(child: _metric(context, 'Duração', durStr)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------
// [NOVO] Card estilo "Apple Fitness" para atividade
// ----------------------------------------------
class _AppleStyleActivityCard extends StatelessWidget {
  final String metricLeftLabel;
  final String metricLeftValue;
  final String metricRightLabel;
  final String metricRightValue;

  final IconData activityIcon;
  final Color activityColor;
  final String activityTitle;
  final String activitySubtitle;

  final String? footerLabel;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenDetails;

  const _AppleStyleActivityCard({
    required this.metricLeftLabel,
    required this.metricLeftValue,
    required this.metricRightLabel,
    required this.metricRightValue,
    required this.activityIcon,
    required this.activityColor,
    required this.activityTitle,
    required this.activitySubtitle,
    required this.onOpenHistory,
    required this.onOpenDetails,
    this.footerLabel,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.0,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1), // mais transparente
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.25)), // borda mais sutil
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Métricas topo
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metricLeftLabel, style: labelStyle),
                          const SizedBox(height: 4),
                          Text(metricLeftValue, style: valueStyle),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metricRightLabel, style: labelStyle),
                          const SizedBox(height: 4),
                          Text(metricRightValue, style: valueStyle),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: Colors.black12),
                // Atividade
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onOpenDetails,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: activityColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(activityIcon, color: Colors.black),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(activityTitle, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(
                                activitySubtitle,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
                if (footerLabel != null) ...[
                  Container(height: 1, color: Colors.black12),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onOpenHistory,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Transform.translate(
                                offset: const Offset(0, 5),
                                child: Text(
                                  footerLabel!,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}