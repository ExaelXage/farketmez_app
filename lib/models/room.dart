class Room {
  final String id;
  final String code;
  final String category;
  final List<String> members;
  final String status;
  final String hostNickname;

  Room({
    required this.id,
    required this.code,
    required this.category,
    required this.members,
    required this.status,
    required this.hostNickname,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['_id'] ?? json['id'] ?? '',
      code: json['code'] ?? '',
      category: json['category'] ?? 'food',
      members: List<String>.from(json['members'] ?? []),
      status: json['status'] ?? 'waiting',
      hostNickname: json['hostNickname'] ?? json['host'] ?? '',
    );
  }

  Room copyWith({
    String? id,
    String? code,
    String? category,
    List<String>? members,
    String? status,
    String? hostNickname,
  }) {
    return Room(
      id: id ?? this.id,
      code: code ?? this.code,
      category: category ?? this.category,
      members: members ?? this.members,
      status: status ?? this.status,
      hostNickname: hostNickname ?? this.hostNickname,
    );
  }
}
