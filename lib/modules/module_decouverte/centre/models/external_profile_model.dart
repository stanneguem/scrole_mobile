import 'package:scrole/shared/models/interest_model.dart';

class ExternalProfileModel {
  final String userId;
  final String username;
  final String displayName;
  final DateTime? birthDate;
  final String? gender;
  final String? bio;
  final String? slogan;
  final String? photoUrl;
  final String? coverUrl;
  final String? country;
  final String? city;
  final bool isPrivate;
  final bool isBlocked;
  final bool isConnected;
  final bool connectionRequestSent;
  final bool incomingConnectionRequest;
  final bool isFollowing;
  final bool isCertified;
  final bool canMessage;
  final int friendCount;
  final int eventsParticipatedCount;
  final int eventsInAgendaCount;
  final int followersCount;
  final int followingCount;
  final int friendsCount;
  final bool followsMe;
  final String relationshipState;
  final String? requestId;
  final DateTime? retryAt;
  final double rating;
  final List<Interest> interests;
  final List<Map<String, dynamic>> activities;

  const ExternalProfileModel({
    required this.userId,
    required this.username,
    required this.displayName,
    this.birthDate,
    this.gender,
    this.bio,
    this.slogan,
    this.photoUrl,
    this.coverUrl,
    this.country,
    this.city,
    this.isPrivate = false,
    this.isBlocked = false,
    this.isConnected = false,
    this.connectionRequestSent = false,
    this.incomingConnectionRequest = false,
    this.isFollowing = false,
    this.isCertified = false,
    this.canMessage = false,
    this.friendCount = 0,
    this.eventsParticipatedCount = 0,
    this.eventsInAgendaCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.friendsCount = 0,
    this.followsMe = false,
    this.relationshipState = 'none',
    this.requestId,
    this.retryAt,
    this.rating = 0.0,
    this.interests = const <Interest>[],
    this.activities = const <Map<String, dynamic>>[],
  });

  int? get age {
    if (birthDate == null) return null;
    final today = DateTime.now();
    int a = today.year - birthDate!.year;
    if (today.month < birthDate!.month || (today.month == birthDate!.month && today.day < birthDate!.day)) {
      a--;
    }
    return a >= 0 ? a : null;
  }

  ExternalProfileModel copyWith({
    bool? isConnected,
    bool? connectionRequestSent,
    bool? isFollowing,
    int? friendCount,
    int? eventsParticipatedCount,
    int? eventsInAgendaCount,
    int? followersCount,
    int? followingCount,
    int? friendsCount,
    bool? followsMe,
    String? relationshipState,
    String? requestId,
    DateTime? retryAt,
    double? rating,
    List<Map<String, dynamic>>? activities,
  }) {
    return ExternalProfileModel(
      userId: userId,
      username: username,
      displayName: displayName,
      birthDate: birthDate,
      gender: gender,
      bio: bio,
      slogan: slogan,
      photoUrl: photoUrl,
      coverUrl: coverUrl,
      country: country,
      city: city,
      isPrivate: isPrivate,
      isBlocked: isBlocked,
      isConnected: isConnected ?? this.isConnected,
      connectionRequestSent: connectionRequestSent ?? this.connectionRequestSent,
      incomingConnectionRequest: incomingConnectionRequest,
      isFollowing: isFollowing ?? this.isFollowing,
      isCertified: isCertified,
      canMessage: canMessage,
      friendCount: friendCount ?? this.friendCount,
      eventsParticipatedCount: eventsParticipatedCount ?? this.eventsParticipatedCount,
      eventsInAgendaCount: eventsInAgendaCount ?? this.eventsInAgendaCount,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      friendsCount: friendsCount ?? this.friendsCount,
      followsMe: followsMe ?? this.followsMe,
      relationshipState: relationshipState ?? this.relationshipState,
      requestId: requestId ?? this.requestId,
      retryAt: retryAt ?? this.retryAt,
      rating: rating ?? this.rating,
      interests: interests,
      activities: activities ?? this.activities,
    );
  }

  factory ExternalProfileModel.fromJson(Map<String, dynamic> json) {
    final first = (json['first_name'] as String? ?? '').trim();
    final last = (json['last_name'] as String? ?? '').trim();
    final display = '$first $last'.trim();
    final rawInterests = json['interests'];
    final interests = rawInterests is List
        ? rawInterests
            .whereType<Map>()
            .map((e) => Interest.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <Interest>[];

    final rawActivities = json['activities'];
    final activities = rawActivities is List
        ? rawActivities.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const <Map<String, dynamic>>[];

    return ExternalProfileModel(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: display.isEmpty ? (json['username'] as String? ?? '') : display,
      birthDate: json['birth_date'] == null ? null : DateTime.tryParse(json['birth_date'].toString()),
      gender: json['gender']?.toString() ?? json['genre']?.toString(),
      bio: json['bio'] as String?,
      slogan: json['slogan'] as String?,
      photoUrl: json['photo_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      country: json['country'] as String?,
      city: json['city'] as String?,
      isPrivate: json['is_private'] == true,
      isBlocked: json['is_blocked'] == true,
      isConnected: json['is_connected'] == true,
      connectionRequestSent: json['connection_request_sent'] == true,
      incomingConnectionRequest: json['incoming_connection_request'] == true,
      isFollowing: json['is_following'] == true,
      isCertified: json['is_certified'] == true || json['is_verified'] == true,
      canMessage: json['can_message'] == true,
      friendCount: (json['friend_count'] as num?)?.toInt() ?? 0,
      eventsParticipatedCount: (json['events_participated'] as num?)?.toInt() ?? (json['events_participated_count'] as num?)?.toInt() ?? 0,
      eventsInAgendaCount: (json['events_in_agenda'] as num?)?.toInt() ?? (json['events_in_agenda_count'] as num?)?.toInt() ?? 0,
      followersCount: (json['followers_count'] as num?)?.toInt() ?? (json['followers'] as num?)?.toInt() ?? 0,
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
      friendsCount: (json['friends_count'] as num?)?.toInt() ?? (json['friend_count'] as num?)?.toInt() ?? 0,
      followsMe: json['follows_me'] == true,
      relationshipState: (json['relationship'] is Map ? (json['relationship']['state'] ?? 'none') : (json['state'] ?? 'none')).toString(),
      requestId: (json['relationship'] is Map ? json['relationship']['request_id'] : json['request_id'])?.toString(),
      retryAt: (json['relationship'] is Map ? json['relationship']['retry_at'] : json['retry_at']) == null ? null : DateTime.tryParse((json['relationship'] is Map ? json['relationship']['retry_at'] : json['retry_at']).toString()),
      rating: (json['rating'] as num?)?.toDouble() ?? (json['profile_rating'] as num?)?.toDouble() ?? 0.0,
      interests: interests,
      activities: activities,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'username': username,
      'first_name': displayName,
      'last_name': '',
      'birth_date': birthDate?.toIso8601String(),
      'gender': gender,
      'bio': bio,
      'slogan': slogan,
      'photo_url': photoUrl,
      'cover_url': coverUrl,
      'country': country,
      'city': city,
      'is_private': isPrivate,
      'is_blocked': isBlocked,
      'is_connected': isConnected,
      'connection_request_sent': connectionRequestSent,
      'incoming_connection_request': incomingConnectionRequest,
      'is_following': isFollowing,
      'is_certified': isCertified,
      'can_message': canMessage,
      'friend_count': friendCount,
      'events_participated': eventsParticipatedCount,
      'events_in_agenda': eventsInAgendaCount,
      'followers_count': followersCount,
      'following_count': followingCount,
      'friends_count': friendsCount,
      'follows_me': followsMe,
      'relationship': {'state': relationshipState, 'request_id': requestId, 'retry_at': retryAt?.toIso8601String()},
      'rating': rating,
    };
  }
}
