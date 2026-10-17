import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Sends keep retrying for a while on network errors (subway), and fail at
  // once on everything else.
  test('network errors are transient', () {
    for (final m in [
      "Send timeout; try again",
      "IO error: Broken pipe (os error 32)",
      "Do not retry IO error: Software caused connection abort (os error 103)",
      "IO error: failed to lookup address information: No address associated with hostname",
    ]) {
      expect(RustPushBackend.isTransientSendError(AnyhowException(m)), isTrue, reason: m);
    }
  });

  test('refusals and unknown errors are not', () {
    for (final m in ["Send error 5032", "Verification Failed", "Failed to generate resource; not retrying"]) {
      expect(RustPushBackend.isTransientSendError(AnyhowException(m)), isFalse, reason: m);
    }
    expect(RustPushBackend.isTransientSendError(StateError("x")), isFalse);
  });
}
