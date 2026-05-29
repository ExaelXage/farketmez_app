class Place {
  final int id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final List<String> types;
  int votes;         // net skor: olumlu - olumsuz
  int positiveVotes; // ham olumlu oy sayısı (eşitlik bozma için)

  Place({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.types,
    this.votes = 0,
    this.positiveVotes = 0,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      lat: (json['lat'] ?? 0).toDouble(),
      lng: (json['lng'] ?? 0).toDouble(),
      types: json['category'] != null ? [json['category'].toString()] : [],
      votes: json['total_score'] ?? json['likes'] ?? json['votes'] ?? 0,
      positiveVotes: json['positive_votes'] ?? json['likes'] ?? 0,
    );
  }
}
