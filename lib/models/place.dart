class Place {
  final int id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final List<String> types;
  int votes;
  int positiveVotes;
  final double? rating;
  final int userRatingCount;
  final int? priceLevel;  // 1=$  2=$$  3=$$$  4=$$$$
  final bool? openNow;

  Place({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.types,
    this.votes = 0,
    this.positiveVotes = 0,
    this.rating,
    this.userRatingCount = 0,
    this.priceLevel,
    this.openNow,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    final rawOpen = json['open_now'];
    bool? openNow;
    if (rawOpen == true || rawOpen == 1) {
      openNow = true;
    } else if (rawOpen == false || rawOpen == 0) {
      openNow = false;
    }

    return Place(
      id:               json['id'] ?? 0,
      name:             json['name'] ?? '',
      address:          json['address'] ?? '',
      lat:              (json['lat'] ?? 0).toDouble(),
      lng:              (json['lng'] ?? 0).toDouble(),
      types:            json['category'] != null ? [json['category'].toString()] : [],
      votes:            json['total_score'] ?? json['likes'] ?? json['votes'] ?? 0,
      positiveVotes:    json['positive_votes'] ?? json['likes'] ?? 0,
      rating:           json['rating'] != null ? (json['rating'] as num).toDouble() : null,
      userRatingCount:  json['user_rating_count'] ?? 0,
      priceLevel:       json['price_level'],
      openNow:          openNow,
    );
  }
}
