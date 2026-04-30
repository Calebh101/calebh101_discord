Future<T?> safematch<T>(RegExp pattern, T Function(RegExp pattern) callback, {Duration timeout = const Duration(seconds: 1),}) async {
  return Future<T?>(() => callback.call(pattern)).timeout(timeout, onTimeout: () => null);
}