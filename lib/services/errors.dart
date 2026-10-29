sealed class AppFailure implements Exception {
  final String message;
  final Object? cause;
  const AppFailure(this.message, [this.cause]);
  @override
  String toString() => message;
}

class AuthFailure extends AppFailure {
  const AuthFailure(super.message, [super.cause]);
}

class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message, [super.cause]);
}

class ServerFailure extends AppFailure {
  final int? statusCode;
  const ServerFailure(String message, {this.statusCode, Object? cause})
      : super(message, cause);
}

class UpdateFailure extends AppFailure {
  const UpdateFailure(super.message, [super.cause]);
}

class UpdateCancelled extends AppFailure {
  const UpdateCancelled() : super('Update cancelled.');
}

AppFailure classifyHttpError(Object e, [StackTrace? st]) {
  final text = e.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('handshake') ||
      text.contains('failed host lookup') ||
      text.contains('connection closed') ||
      text.contains('network is unreachable') ||
      text.contains('clientexception')) {
    return NetworkFailure('Can\'t reach the server. Check your connection.', e);
  }
  return ServerFailure('Server error: $e', cause: e);
}
