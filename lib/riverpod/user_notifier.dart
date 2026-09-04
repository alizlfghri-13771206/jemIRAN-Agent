import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

class UserState {
  final String username;
  final String phone;
  final String? profilePicUrl;
  final String email;

  const UserState({
    this.username = 'کاربر',
    this.phone = '',
    this.email = '',
    this.profilePicUrl,
  });

  String get displayIdentity =>
      phone.isNotEmpty ? phone : (email.isNotEmpty ? email : '');

  bool get identityIsPhone => phone.isNotEmpty;

  UserState copyWith({
    String? username,
    String? phone,
    String? email,
    String? profilePicUrl,
    bool clearPic = false,
  }) {
    return UserState(
      username: username ?? this.username,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      profilePicUrl: clearPic ? null : (profilePicUrl ?? this.profilePicUrl),
    );
  }
}

class UserNotifier extends StateNotifier<UserState> {
  UserNotifier() : super(const UserState());

  void setUsername(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) state = state.copyWith(username: trimmed);
  }

  void setPhone(String phone) {
    state = state.copyWith(phone: phone);
  }

  void setProfilePic(String? url) {
    if (url == null || url.isEmpty) {
      state = state.copyWith(clearPic: true);
    } else {
      state = state.copyWith(profilePicUrl: url);
    }
  }

  void setFromMap(Map<String, dynamic> data) {
    final name = (data['full_name'] as String? ?? '').trim();
    final phone = (data['phone'] as String? ?? '').trim();
    final email = (data['email'] as String? ?? '').trim();
    final pic = data['profile_pic'] as String?;
    state = UserState(
      username: name.isNotEmpty ? name : 'کاربر',
      phone: phone,
      email: email,
      profilePicUrl: (pic != null && pic.isNotEmpty) ? pic : null,
    );
  }
}

final userProvider = StateNotifierProvider<UserNotifier, UserState>(
  (ref) => UserNotifier(),
);

final usernameProvider = Provider<String>((ref) {
  return ref.watch(userProvider).phone;
});
