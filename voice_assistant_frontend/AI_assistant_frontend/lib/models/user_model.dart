class UserModel {
  final String id;
  final String name;
  final String username;
  final String? email;
  final String? avatarUrl;

  UserModel({
    required this.id,
    required this.name,
    required this.username,
    this.email,
    this.avatarUrl,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: (json['userId'] ?? json['id'] ?? '').toString(),
        name: (json['name'] ?? json['username'] ?? 'User').toString(),
        username: (json['username'] ?? '').toString(),
        email: json['email']?.toString(),
        avatarUrl: json['avatarUrl']?.toString(),
      );
}
