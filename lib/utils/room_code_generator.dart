import 'dart:math';

class RoomCodeGenerator {
  static const _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static final _random = Random();

  static String generate() {
    return List.generate(
      6,
      (_) => _chars[_random.nextInt(_chars.length)],
    ).join();
  }
}
