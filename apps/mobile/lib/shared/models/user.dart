class UserDto {
  const UserDto({
    required this.id,
    required this.phone,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String phone;
  final String? displayName;
  final String? avatarUrl;

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
        id: json['id'] as String,
        phone: json['phone'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}
