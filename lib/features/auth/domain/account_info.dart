import '../../../shared/json_read.dart';

/// Minimum danych o koncie potrzebne do potwierdzenia, że sesja działa.
/// Celowo bez nazwisk, loginu i e-maila.
class AccountInfo {
  const AccountInfo({this.accountFirstName, this.studentFirstName});

  final String? accountFirstName;
  final String? studentFirstName;

  /// `Me` → `{"Me": {"Account": {...}, "User": {...}}}`. Zwraca `null`, gdy
  /// brakuje obiektu konta — samo `{"Me": {}}` nie potwierdza sesji.
  static AccountInfo? tryParse(Map<String, dynamic> json) {
    final me = json['Me'];
    if (me is! Map<String, dynamic>) return null;
    final account = me['Account'];
    final user = me['User'];
    if (account is! Map && user is! Map) {
      return null;
    }
    return AccountInfo(
      accountFirstName: account is Map
          ? readString(account['FirstName'])
          : null,
      studentFirstName: user is Map ? readString(user['FirstName']) : null,
    );
  }
}
