// Copyright (c) 2024-2026 protocentral
// SPDX-License-Identifier: MIT

part of 'device_manager_screen.dart';

// Health Store (HPI_HS) + record viewer / chart
// ---------------------------------------------------------------------------
// Health Store panel (HPI_HS group 0x1000 — ProtoCentral only)
// ---------------------------------------------------------------------------

class _HealthStorePanel extends StatefulWidget {
  const _HealthStorePanel();

  @override
  State<_HealthStorePanel> createState() => _HealthStorePanelState();
}

class _HealthStorePanelState extends State<_HealthStorePanel> {
  Map<int, HsType> _types = const {};
  List<HsSample> _samples = const [];
  HsSummary? _summary;
  List<HsRecordHeader> _records = const [];

  bool _busy = false;
  int _fetched = 0;
  String? _status;
  bool _statusIsError = false;

  void _setStatus(String s, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = s;
      _statusIsError = error;
    });
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
    } catch (e) {
      _setStatus('$label failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetchTypes(SmpController smp) => _run('TYPES', () async {
        final t = await smp.hs!.types();
        if (mounted) setState(() => _types = t);
        _setStatus('Fetched ${t.length} type registry entries.');
      });

  Future<void> _syncAll(SmpController smp) => _run('SYNC', () async {
        setState(() => _fetched = 0);
        final s = await smp.hs!.syncAll(onProgress: (n) {
          if (mounted) setState(() => _fetched = n);
        });
        if (mounted) setState(() => _samples = s);
        _setStatus('Synced ${s.length} samples.');
      });

  Future<void> _fetchSummary(SmpController smp) => _run('SUMMARY', () async {
        final m = await smp.hs!.summary();
        final s = HsSummary.fromMap(m);
        if (mounted) setState(() => _summary = s);
        _setStatus('Summary: ${s.cards.length} fields.');
      });

  Future<void> _listRecords(SmpController smp) => _run('RECORDS', () async {
        final r = await smp.hs!.recordsList();
        if (mounted) setState(() => _records = r);
        _setStatus('${r.length} record session(s).');
      });

  Future<void> _viewRecord(
      BuildContext context, SmpController smp, HsRecordHeader h) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RecordViewerDialog(hs: smp.hs!, header: h),
    );
  }

  Future<void> _ackHead(SmpController smp) => _run('ACK', () async {
        final head = smp.hsHello?.head ?? 0;
        await smp.hs!.ack(head);
        _setStatus('ACKed seq $head (device may drop retained ≤ that).');
      });

  Future<void> _exportCsv() async {
    if (_samples.isEmpty) {
      _setStatus('Nothing to export — run SYNC first.', error: true);
      return;
    }
    final loc = await getSaveLocation(suggestedName: 'hpi_hs_samples.csv');
    if (loc == null) return;
    final b = StringBuffer('seq,ts_utc_iso,type_id,type_key,value,real,unit,quality\n');
    for (final s in _samples) {
      final t = _types[s.type];
      final real = t != null ? s.real(t).toString() : '';
      b.writeln('${s.seq},${s.timestamp.toIso8601String()},${s.type},'
          '${t?.key ?? ''},${s.value},$real,${t?.unit ?? ''},'
          '"${HsQuality.describe(s.quality)}"');
    }
    await File(loc.path).writeAsString(b.toString());
    _setStatus('Exported ${_samples.length} samples → ${loc.path}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smp = context.watch<SmpController>();
    final hello = smp.hsHello;
    final busy = _busy;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Health Store · HPI_HS (0x1000)',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        if (hello != null)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _MiniTag('schema v${hello.schema}'),
              _MiniTag('group v${hello.group}'),
              _MiniTag('dev ${hello.dev}'),
              _MiniTag('head ${hello.head}'),
              _MiniTag('${hello.types} types'),
            ],
          ),
        const Divider(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => _fetchTypes(smp),
              icon: const Icon(Icons.list_alt, size: 16),
              label: const Text('Types'),
            ),
            FilledButton.icon(
              onPressed: busy ? null : () => _syncAll(smp),
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Sync all'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _fetchSummary(smp),
              icon: const Icon(Icons.summarize, size: 16),
              label: const Text('Summary'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _listRecords(smp),
              icon: const Icon(Icons.monitor_heart_outlined, size: 16),
              label: const Text('Records'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _ackHead(smp),
              icon: const Icon(Icons.done_all, size: 16),
              label: const Text('ACK head'),
            ),
            OutlinedButton.icon(
              onPressed: (busy || _samples.isEmpty) ? null : _exportCsv,
              icon: const Icon(Icons.save_alt, size: 16),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        if (busy && _fetched > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Synced $_fetched…', style: theme.textTheme.labelSmall),
        ],
        if (_status != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_status!,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'JetBrainsMono',
                  color: _statusIsError
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant)),
        ],

        // Type registry
        if (_types.isNotEmpty) ...[
          const Divider(height: AppSpacing.lg),
          Text('Type registry (${_types.length})',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          for (final t in _types.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '0x${t.id.toRadixString(16).padLeft(2, '0')}  '
                '${t.key.padRight(14)} ${t.unit.padRight(6)} '
                '/${t.scale}  ${t.klass.label}${t.derived ? ' (derived)' : ''}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'JetBrainsMono'),
              ),
            ),
        ],

        // Samples
        if (_samples.isNotEmpty) ...[
          const Divider(height: AppSpacing.lg),
          Text('Samples (${_samples.length}, showing last 100)',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          for (final s in _samples.reversed.take(100))
            _SampleLine(sample: s, type: _types[s.type]),
        ],

        // Records (episodic raw-signal sessions)
        if (_records.isNotEmpty) ...[
          const Divider(height: AppSpacing.lg),
          Text('Records (${_records.length})',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          for (final r in _records)
            _RecordRow(
              header: r,
              onView: busy ? null : () => _viewRecord(context, smp, r),
            ),
        ],

        // Summary dashboard
        if (_summary != null) ...[
          const Divider(height: AppSpacing.lg),
          Text('Summary', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          if (_summary!.cards.isEmpty)
            Text('(empty)',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [for (final c in _summary!.cards) _SummaryCard(card: c)],
            ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final HsSummaryCard card;
  const _SummaryCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(card.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(card.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              if (card.unit != null) ...[
                const SizedBox(width: 3),
                Text(card.unit!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final HsRecordHeader header;
  final VoidCallback? onView;
  const _RecordRow({required this.header, required this.onView});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String p(int n) => n.toString().padLeft(2, '0');
    final t = header.startTime.toLocal();
    final when = header.startTs == 0
        ? ''
        : '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(Icons.show_chart, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('#${header.id} · ${header.signalName}',
                        style: theme.textTheme.bodyMedium),
                    if (header.isPartial) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _MiniTag('partial'),
                    ],
                  ],
                ),
                Text(
                  '$when · ${header.sampleRate} Hz · ${header.nSamples} samp · '
                  '${header.channels}ch · ${header.byteLen} B',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'JetBrainsMono'),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('View'),
          ),
        ],
      ),
    );
  }
}

class _SampleLine extends StatelessWidget {
  final HsSample sample;
  final HsType? type;
  const _SampleLine({required this.sample, required this.type});

  static String _fmtTs(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = type;
    final real = t != null
        ? '${sample.real(t).toStringAsFixed(t.scale > 1 ? 2 : 0)} ${t.unit}'
        : 'v=${sample.value}';
    final key = t?.key ?? '0x${sample.type.toRadixString(16)}';
    final ts = _fmtTs(sample.timestamp.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '#${sample.seq}  $ts  ${key.padRight(14)} $real'
        '${sample.isValid ? '' : '  [!valid]'}',
        style: theme.textTheme.bodySmall
            ?.copyWith(fontFamily: 'JetBrainsMono', fontSize: 11.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Record viewer — downloads a record, CRC-verifies, and charts the samples
// ---------------------------------------------------------------------------

class _RecordViewerDialog extends StatefulWidget {
  final HpiHs hs;
  final HsRecordHeader header;
  const _RecordViewerDialog({required this.hs, required this.header});

  @override
  State<_RecordViewerDialog> createState() => _RecordViewerDialogState();
}

class _RecordViewerDialogState extends State<_RecordViewerDialog> {
  bool _loading = true;
  String? _error;
  int _done = 0;
  int _total = 0;
  Uint8List? _raw;
  bool _crcOk = false;
  HsRecordSamples? _decoded;
  bool _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    try {
      final dl = await widget.hs.downloadRecord(widget.header,
          onProgress: (d, t) {
        if (mounted) setState(() {
          _done = d;
          _total = t;
        });
      });
      final decoded = HsRecordSamples.decode(widget.header, dl.data);
      if (!mounted) return;
      setState(() {
        _raw = dl.data;
        _crcOk = dl.crcOk;
        _decoded = decoded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _saveRaw() async {
    final raw = _raw;
    if (raw == null) return;
    final loc = await getSaveLocation(
        suggestedName: 'record_${widget.header.id}.bin');
    if (loc == null) return;
    await File(loc.path).writeAsBytes(raw);
    setState(() => _note = 'Saved raw → ${loc.path}');
  }

  Future<void> _ack() async {
    setState(() => _busy = true);
    try {
      await widget.hs.recordsAck(widget.header.id);
      setState(() => _note = 'ACKed — device may drop record #${widget.header.id}.');
    } catch (e) {
      setState(() => _note = 'ACK failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = widget.header;
    final d = _decoded;
    return Dialog(
      child: SizedBox(
        width: 760,
        height: 540,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Record #${h.id} · ${h.signalName}',
                        style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_loading)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 220,
                          child: LinearProgressIndicator(
                              value: _total == 0 ? null : _done / _total),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text('Downloading $_done / $_total B',
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Text('Download failed: $_error',
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                )
              else if (d != null) ...[
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _CrcChip(ok: _crcOk),
                    _MiniTag('${d.sampleCount} samp'),
                    _MiniTag('${d.channels}ch'),
                    _MiniTag('${d.bytesPerSample}B/samp'),
                    _MiniTag('${h.sampleRate} Hz'),
                    if (d.assumed)
                      _MiniTag('format assumed'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(child: _RecordChart(samples: d)),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _saveRaw,
                      icon: const Icon(Icons.save_alt, size: 16),
                      label: const Text('Save raw'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _ack,
                      icon: const Icon(Icons.done_all, size: 16),
                      label: const Text('ACK (drop on device)'),
                    ),
                    const Spacer(),
                    if (_note != null)
                      Flexible(
                        child: Text(_note!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CrcChip extends StatelessWidget {
  final bool ok;
  const _CrcChip({required this.ok});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = ok ? scheme.secondary : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.verified : Icons.error_outline, size: 14, color: c),
          const SizedBox(width: 4),
          Text(ok ? 'CRC ok' : 'CRC mismatch',
              style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Static multi-channel line chart of decoded record samples (downsampled).
class _RecordChart extends StatelessWidget {
  final HsRecordSamples samples;
  const _RecordChart({required this.samples});

  static const int _maxPoints = 1500;
  static const int _maxChannels = 4;
  static const List<Color> _palette = [
    Color(0xFF4DD0E1),
    Color(0xFFFF8A65),
    Color(0xFFAED581),
    Color(0xFFBA68C8),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final channels = samples.data.take(_maxChannels).toList();
    if (channels.isEmpty || channels.first.isEmpty) {
      return Center(
        child: Text('No samples to plot.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    double minY = double.infinity, maxY = -double.infinity;
    final bars = <LineChartBarData>[];
    for (var c = 0; c < channels.length; c++) {
      final ch = channels[c];
      final step = (ch.length / _maxPoints).ceil().clamp(1, ch.length);
      final spots = <FlSpot>[];
      for (var i = 0; i < ch.length; i += step) {
        final y = ch[i];
        spots.add(FlSpot(i.toDouble(), y));
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      bars.add(LineChartBarData(
        spots: spots,
        isCurved: false,
        barWidth: 1,
        color: _palette[c % _palette.length],
        dotData: const FlDotData(show: false),
      ));
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    final pad = (maxY - minY) * 0.05;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        lineBarsData: bars,
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: const FlTitlesData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: scheme.outlineVariant.withValues(alpha: 0.3), strokeWidth: 1),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}
