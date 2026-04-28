import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ngo_connect/services/geocoding_service.dart';
import 'package:ngo_connect/utils/validators.dart'
    show
        validateNgoRegistration,
        validateNeedCard,
        isValidTransition,
        kKanbanOrder,
        computeAverageRating,
        computeRatingBonus;

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── AUTH ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
    String role, {
    Map<String, dynamic>? ngoData,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user!.uid;

      final userDoc = <String, dynamic>{
        'name': name,
        'email': email,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (role == 'volunteer') {
        userDoc.addAll({
          'skills': <String>[],
          'languages': <String>[],
          'availability': '',
          'location': '',
          'lat': 0.0,
          'lng': 0.0,
          'preferredCauses': <String>[],
          'pastExperience': '',
          'averageRating': 0.0,
          'completedTaskCount': 0,
        });
      } else if (role == 'ngo') {
        userDoc['ngoId'] = uid;
      }

      await _db.collection('users').doc(uid).set(userDoc);

      if (role == 'ngo' && ngoData != null) {
        await createOrUpdateNgo(uid, {
          ...ngoData,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return {'success': true, 'uid': uid, 'role': role};
    } on FirebaseAuthException catch (e) {
      return {'error': e.message ?? 'Registration failed'};
    }
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final doc =
          await _db.collection('users').doc(cred.user!.uid).get();
      final data = doc.data() ?? {};
      final role = data['role'];
      if (role == null) {
        return {'error': 'User profile not found. Please register again.'};
      }
      return {
        'success': true,
        'uid': cred.user!.uid,
        'role': role,
        'name': data['name'] ?? '',
      };
    } on FirebaseAuthException catch (e) {
      return {'error': e.message ?? 'Login failed'};
    }
  }

  static Future<void> logout() async => _auth.signOut();

  // ── NGO ───────────────────────────────────────────────────────────────────

  /// Creates or updates an NGO document in Firestore.
  /// If [data] contains an 'address' field, the address is geocoded via
  /// Nominatim and the resulting lat/lng are stored alongside it.
  /// Requirement 1.2: resolve address → lat/lng and store in `ngos` table.
  static Future<void> createOrUpdateNgo(
      String uid, Map<String, dynamic> data) async {
    final enriched = Map<String, dynamic>.from(data);

    final address = enriched['address'] as String?;
    if (address != null && address.trim().isNotEmpty) {
      final geo = await GeocodingService.geocodeAddress(address);
      if (geo != null) {
        enriched['lat'] = geo.lat;
        enriched['lng'] = geo.lng;
      }
    }

    // Geocode coordinator address if provided.
    final coordAddress = enriched['coordinatorAddress'] as String?;
    if (coordAddress != null && coordAddress.trim().isNotEmpty) {
      final geo = await GeocodingService.geocodeAddress(coordAddress);
      if (geo != null) {
        enriched['coordinatorLat'] = geo.lat;
        enriched['coordinatorLng'] = geo.lng;
      }
    }

    await _db.collection('ngos').doc(uid).set(enriched, SetOptions(merge: true));
  }

  static Future<Map<String, dynamic>?> getNgoProfile(String uid) async {
    final doc = await _db.collection('ngos').doc(uid).get();
    return doc.data();
  }

  // ── DOCUMENTS ─────────────────────────────────────────────────────────────

  /// Returns a live stream of document metadata for the given NGO.
  static Stream<QuerySnapshot> getDocumentsStream(String ngoId) {
    // No orderBy — sort client-side to avoid composite index requirement.
    return _db
        .collection('ngo_documents')
        .where('ngoId', isEqualTo: ngoId)
        .snapshots();
  }

  /// Writes document metadata to Firestore after a successful Storage upload.
  static Future<String> saveDocumentMetadata(
      Map<String, dynamic> metadata) async {
    final doc = await _db.collection('ngo_documents').add({
      ...metadata,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  // ── USER ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  static Future<void> updateVolunteerProfile(
      String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  // ── NEEDS ─────────────────────────────────────────────────────────────────

  static Future<String> createNeed(Map<String, dynamic> need) async {
    final doc = await _db.collection('needs').add({
      ...need,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open',
      'applicantCount': 0,
    });
    return doc.id;
  }

  static Stream<QuerySnapshot> getNeedsStream({
    String? ngoId,
    String? status,
  }) {
    Query q = _db.collection('needs');
    if (ngoId != null) q = q.where('ngoId', isEqualTo: ngoId);
    if (status != null) q = q.where('status', isEqualTo: status);
    // No orderBy — sort client-side to avoid composite index requirement.
    return q.snapshots();
  }

  static Future<void> updateNeed(
      String needId, Map<String, dynamic> data) async {
    await _db.collection('needs').doc(needId).update(data);
  }

  // ── MATCHING ──────────────────────────────────────────────────────────────

  static Future<void> storeMatches(
      String needId, List<Map<String, dynamic>> matches) async {
    final batch = _db.batch();
    for (final m in matches) {
      final ref = _db.collection('matches').doc();
      batch.set(ref, {
        ...m,
        'needId': needId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static Stream<QuerySnapshot> getMatchesStream(String volunteerId) {
    // No orderBy — sort client-side to avoid composite index requirement.
    return _db
        .collection('matches')
        .where('volunteerId', isEqualTo: volunteerId)
        .snapshots();
  }

  // ── ASSIGNMENTS ───────────────────────────────────────────────────────────

  static Future<String> createAssignment(
      Map<String, dynamic> assignment) async {
    final doc = await _db.collection('task_assignments').add({
      ...assignment,
      'status': 'invited',
      'invitedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> updateAssignmentStatus(
      String assignmentId, String status) async {
    final doc = await _db
        .collection('task_assignments')
        .doc(assignmentId)
        .get();
    if (!doc.exists) {
      throw Exception('Assignment "$assignmentId" not found.');
    }
    final data = doc.data()!;
    final currentStatus = data['status'] as String? ?? 'invited';
    final error = isValidTransition(currentStatus, status);
    if (error != null) {
      throw Exception(error);
    }

    final update = <String, dynamic>{'status': status};
    switch (status) {
      case 'accepted':
        update['acceptedAt'] = FieldValue.serverTimestamp();
        // Increment applicantCount on the need
        final needId = data['needId'] as String?;
        if (needId != null) {
          await _db.collection('needs').doc(needId).update({
            'applicantCount': FieldValue.increment(1),
          });
        }
        break;
      case 'in-progress':
        update['startedAt'] = FieldValue.serverTimestamp();
        // Mark need as in-progress
        final needId = data['needId'] as String?;
        if (needId != null) {
          await _db.collection('needs').doc(needId).update({'status': 'in-progress'});
        }
        break;
      case 'reported':
        update['reportedAt'] = FieldValue.serverTimestamp();
        break;
      case 'verified':
        update['verifiedAt'] = FieldValue.serverTimestamp();
        break;
      case 'closed':
        update['closedAt'] = FieldValue.serverTimestamp();
        // Mark need as closed and increment completedTaskCount on volunteer
        final needId = data['needId'] as String?;
        final volunteerId = data['volunteerId'] as String?;
        if (needId != null) {
          await _db.collection('needs').doc(needId).update({'status': 'closed'});
        }
        if (volunteerId != null) {
          await _db.collection('users').doc(volunteerId).update({
            'completedTaskCount': FieldValue.increment(1),
          });
        }
        break;
    }
    await _db.collection('task_assignments').doc(assignmentId).update(update);
  }

  /// Marks an assignment as declined (Requirement 6.3).
  /// Declined is a terminal state stored as a separate field, not in the
  /// Kanban order, so we write it directly without transition validation.
  static Future<void> declineAssignment(String assignmentId) async {
    await _db.collection('task_assignments').doc(assignmentId).update({
      'status': 'declined',
      'declinedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot> getAssignmentsStream({
    String? needId,
    String? volunteerId,
    String? ngoId,
  }) {
    Query q = _db.collection('task_assignments');
    if (needId != null) q = q.where('needId', isEqualTo: needId);
    if (volunteerId != null) q = q.where('volunteerId', isEqualTo: volunteerId);
    if (ngoId != null) q = q.where('ngoId', isEqualTo: ngoId);
    return q.snapshots();
  }

  // ── CHAT ──────────────────────────────────────────────────────────────────

  static Future<void> ensureChatRoom(
      String taskId, List<String> participantIds) async {
    final ref = _db.collection('chat_rooms').doc(taskId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'needId': taskId,
        'createdAt': FieldValue.serverTimestamp(),
        'participantIds': participantIds,
      });
    } else {
      // merge any new participants
      await ref.update({
        'participantIds': FieldValue.arrayUnion(participantIds),
      });
    }
  }

  static Future<void> sendMessage(
      String roomId, Map<String, dynamic> message) async {
    await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .add({
      ...message,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot> getMessagesStream(String roomId) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('sentAt')
        .snapshots();
  }

  // ── NOTIFICATIONS ─────────────────────────────────────────────────────────

  static Future<void> createNotification(
      String uid, Map<String, dynamic> notification) async {
    await _db.collection('notifications').add({
      ...notification,
      'recipientUid': uid,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot> getNotificationsStream(String uid) {
    // No orderBy — sort client-side to avoid composite index requirement.
    return _db
        .collection('notifications')
        .where('recipientUid', isEqualTo: uid)
        .snapshots();
  }

  static Future<void> markNotificationRead(String notificationId) async {
    await _db
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  // ── RATINGS ───────────────────────────────────────────────────────────────

  static Future<void> submitRating(Map<String, dynamic> rating) async {
    await _db.collection('ratings').add({
      ...rating,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await recomputeAverageRating(rating['volunteerId'] as String);
  }

  static Future<void> recomputeAverageRating(String volunteerId) async {
    final snap = await _db
        .collection('ratings')
        .where('volunteerId', isEqualTo: volunteerId)
        .get();
    if (snap.docs.isEmpty) return;
    final stars = snap.docs
        .map((d) => (d.data()['stars'] as num?) ?? 0)
        .toList();
    final avg = computeAverageRating(stars);
    await _db
        .collection('users')
        .doc(volunteerId)
        .update({'averageRating': avg});
  }

  // ── ANALYTICS ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getNgoAnalytics(String ngoId) async {
    final needs = await _db
        .collection('needs')
        .where('ngoId', isEqualTo: ngoId)
        .get();
    final open = needs.docs.where((d) => d['status'] == 'open').length;
    final fulfilled =
        needs.docs.where((d) => d['status'] == 'closed').length;
    final assignments = await _db
        .collection('task_assignments')
        .where('ngoId', isEqualTo: ngoId)
        .get();
    final activeVolunteers = assignments.docs
        .map((d) => d['volunteerId'])
        .toSet()
        .length;
    return {
      'needsPosted': needs.docs.length,
      'openNeeds': open,
      'fulfilledNeeds': fulfilled,
      'activeVolunteers': activeVolunteers,
    };
  }
}
