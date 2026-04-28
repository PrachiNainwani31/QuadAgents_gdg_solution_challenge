import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ngo_connect/utils/validators.dart' show computeRatingBonus;
import 'dart:convert';
import 'dart:math' as math;

class MatchingService {
  static final _db = FirebaseFirestore.instance;
  static final _model = GenerativeModel(
    model: 'gemini-1.0-pro',
    apiKey: 'AIzaSyDy_2RYm6gUH2W-JvmLheSV6j21cun9iQ8',
  );

  // Rule-based + Gemini re-ranked matching: volunteer → open needs
  static Future<List<Map<String, dynamic>>> matchVolunteerToNeeds(
      String volunteerId) async {
    final volunteerDoc = await _db.collection('users').doc(volunteerId).get();
    if (!volunteerDoc.exists) return [];
    final volunteer = volunteerDoc.data()!;

    final needsSnap = await _db
        .collection('needs')
        .where('status', isEqualTo: 'open')
        .get();

    if (needsSnap.docs.isEmpty) return [];

    // Score every open need against this volunteer
    final scored = <Map<String, dynamic>>[];
    for (final nDoc in needsSnap.docs) {
      final need = nDoc.data();
      final skill = computeSkillScore(
          List.from(volunteer['skills'] ?? []),
          List.from(need['skills'] ?? []));
      final proximity = computeProximityScore(
          (volunteer['lat'] as num?)?.toDouble() ?? 0.0,
          (volunteer['lng'] as num?)?.toDouble() ?? 0.0,
          (need['lat'] as num?)?.toDouble() ?? 0.0,
          (need['lng'] as num?)?.toDouble() ?? 0.0);
      final availability = computeAvailabilityScore(
          need['schedule'] as String? ?? '',
          volunteer['availability'] as String? ?? '');
      final composite = computeCompositeScore(skill, proximity, availability);
      final ratingBonus =
          computeRatingBonus((volunteer['averageRating'] as num?)?.toDouble() ?? 0.0);
      scored.add({
        'needId': nDoc.id,
        'volunteerId': volunteerId,
        'skillScore': skill,
        'proximityScore': proximity,
        'availabilityScore': availability,
        'compositeScore': composite,
        'ratingBonus': ratingBonus,
        'finalScore': composite * (1 + ratingBonus),
        'geminiReason': '',
      });
    }

    scored.sort((a, b) =>
        (b['finalScore'] as double).compareTo(a['finalScore'] as double));
    final top10 = scored.take(10).toList();

    // Re-ranking via backend
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/match/volunteer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'matches': top10, 'skills': volunteer['skills']}),
      );
      if (response.statusCode == 200) {
        final reranked = List<Map<String, dynamic>>.from(jsonDecode(response.body)['matches'] ?? top10);
        await _storeMatches(reranked);
        return reranked;
      }
    } catch (_) {
      // Fall back to rule-based ranking
    }

    await _storeMatches(top10);
    return top10;
  }

  // Priority ranker — score urgency of needs via backend
  static Future<List<Map<String, dynamic>>> prioritizeNeeds(
      List<Map<String, dynamic>> needs) async {
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/match/prioritize-needs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'needs': needs}),
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body)['ranked_needs'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  // Text parser — extract needs from uploaded survey/doc text
  static Future<List<Map<String, dynamic>>> extractNeedsFromText(
      String rawText) async {
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/match/parse-text'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': rawText}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['needs'] ?? []);
      }
    } catch (e) {
      // ignore, return empty
    }
    return [];
  }

  // ── Pure scoring functions ─────────────────────────────────────────────────

  /// Skill overlap: Jaccard similarity × 100, result in [0, 100].
  static double computeSkillScore(List skills1, List skills2) {
    if (skills1.isEmpty && skills2.isEmpty) return 100.0;
    if (skills1.isEmpty || skills2.isEmpty) return 0.0;
    final set1 = skills1.map((s) => s.toString().toLowerCase()).toSet();
    final set2 = skills2.map((s) => s.toString().toLowerCase()).toSet();
    final intersection = set1.intersection(set2).length;
    final union = set1.union(set2).length;
    return (intersection / union) * 100.0;
  }

  /// Haversine distance in km between two lat/lng pairs.
  static double haversineDistanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0; // Earth radius in km
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;

  /// Proximity score: max(0, 100 - distanceKm), capped at 100.
  static double computeProximityScore(
      double lat1, double lng1, double lat2, double lng2) {
    final dist = haversineDistanceKm(lat1, lng1, lat2, lng2);
    return math.max(0.0, 100.0 - dist).clamp(0.0, 100.0);
  }

  /// Availability score: exact match = 100, partial = 50, none = 0.
  static double computeAvailabilityScore(
      String needSchedule, String volunteerAvailability) {
    final n = needSchedule.trim().toLowerCase();
    final v = volunteerAvailability.trim().toLowerCase();
    if (n.isEmpty || v.isEmpty) return 0.0;
    if (n == v) return 100.0;
    // Partial: one contains the other or both contain a common keyword
    if (n.contains(v) || v.contains(n)) return 50.0;
    const flexibleKeywords = ['flexible', 'full-time', 'anytime'];
    if (flexibleKeywords.any((k) => v.contains(k))) return 50.0;
    return 0.0;
  }

  /// Composite score: 0.5×skill + 0.3×proximity + 0.2×availability.
  static double computeCompositeScore(
      double skillScore, double proximityScore, double availabilityScore) {
    return 0.5 * skillScore + 0.3 * proximityScore + 0.2 * availabilityScore;
  }

  // ── matchNeedToVolunteers ──────────────────────────────────────────────────

  /// Scores all available volunteers against a need, takes top 10,
  /// re-ranks with Gemini, stores results in `matches`, and sends
  /// notifications to the top 5 ranked volunteers (Requirement 5.2).
  static Future<List<Map<String, dynamic>>> matchNeedToVolunteers(
      String needId) async {
    final needDoc = await _db.collection('needs').doc(needId).get();
    if (!needDoc.exists) return [];
    final need = needDoc.data()!;

    final volunteersSnap = await _db
        .collection('users')
        .where('role', isEqualTo: 'volunteer')
        .get();
    if (volunteersSnap.docs.isEmpty) return [];

    final scored = <Map<String, dynamic>>[];
    for (final vDoc in volunteersSnap.docs) {
      final v = vDoc.data();
      final skill = computeSkillScore(
          List.from(need['skills'] ?? []), List.from(v['skills'] ?? []));
      final proximity = computeProximityScore(
          (need['lat'] as num?)?.toDouble() ?? 0.0,
          (need['lng'] as num?)?.toDouble() ?? 0.0,
          (v['lat'] as num?)?.toDouble() ?? 0.0,
          (v['lng'] as num?)?.toDouble() ?? 0.0);
      final availability = computeAvailabilityScore(
          need['schedule'] as String? ?? '',
          v['availability'] as String? ?? '');
      final composite =
          computeCompositeScore(skill, proximity, availability);
      final ratingBonus =
          computeRatingBonus((v['averageRating'] as num?)?.toDouble() ?? 0.0);
      scored.add({
        'volunteerId': vDoc.id,
        'needId': needId,
        'skillScore': skill,
        'proximityScore': proximity,
        'availabilityScore': availability,
        'compositeScore': composite,
        'ratingBonus': ratingBonus,
        'finalScore': composite * (1 + ratingBonus),
        'geminiReason': '',
      });
    }

    scored.sort((a, b) =>
        (b['finalScore'] as double).compareTo(a['finalScore'] as double));
    final top10 = scored.take(10).toList();

    // Re-ranking via backend (best-effort, falls back to rule-based top10)
    List<Map<String, dynamic>> finalMatches = top10;
    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/match/volunteer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'volunteer_id': 'system', 'matches': top10}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['matches'] != null) {
          finalMatches = List<Map<String, dynamic>>.from(data['matches']);
        }
      }
    } catch (_) {
      // Fall back to rule-based ranking
    }

    await _storeMatches(finalMatches);

    // Notify top 5 volunteers (Requirement 5.2)
    final top5 = finalMatches.take(5).toList();
    for (final match in top5) {
      final vid = match['volunteerId'] as String?;
      if (vid != null) {
        await _db.collection('notifications').add({
          'recipientUid': vid,
          'type': 'match_invite',
          'title': 'New need match: ${need['title'] ?? ''}',
          'body': 'You have been matched to a new volunteer opportunity.',
          'relatedId': needId,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    return finalMatches;
  }

  /// Persists match results to the `matches` Firestore collection.
  static Future<void> _storeMatches(
      List<Map<String, dynamic>> matches) async {
    final batch = _db.batch();
    for (final m in matches) {
      final ref = _db.collection('matches').doc();
      batch.set(ref, {
        ...m,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}