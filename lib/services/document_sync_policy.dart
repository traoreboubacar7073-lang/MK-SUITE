import 'dart:convert';

enum DocumentSyncDecision { replace, keep, conflict }

/// Document contents are snapshots, never the union of independent line IDs.
/// Repeated identical lines remain repeated (multiset comparison).
DocumentSyncDecision documentSyncDecision({
  required int? localRevision,
  required int remoteRevision,
  required List<Map<String, dynamic>> localLines,
  required List<Map<String, dynamic>> remoteLines,
}) {
  if (localRevision == null || remoteRevision > localRevision) {
    return DocumentSyncDecision.replace;
  }
  if (remoteRevision < localRevision) return DocumentSyncDecision.keep;
  List<String> signature(List<Map<String, dynamic>> lines) =>
      lines
          .map(
            (r) => jsonEncode([
              (r['quantite'] as num?)?.toDouble(),
              r['description'],
              (r['prix_unitaire'] as num?)?.toDouble(),
              (r['total_ligne'] as num?)?.toDouble(),
            ]),
          )
          .toList()
        ..sort();
  return jsonEncode(signature(localLines)) == jsonEncode(signature(remoteLines))
      ? DocumentSyncDecision.keep
      : DocumentSyncDecision.conflict;
}
